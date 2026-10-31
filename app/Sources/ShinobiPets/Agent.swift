import AppKit

/// Turns a typed command into actions. Uses Claude when an API key is set, otherwise a small offline parser.
@MainActor
final class Agent {
    static let shared = Agent()

    private var history: [[String: Any]] = []   // append-only; reset (never trimmed) when it gets old
    private var lastUse = Date.distantPast
    private(set) var running = false
    private var webSearchUnavailable = false

    func handle(_ text: String, pet: Pet) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !running else { pet.say("One mission at a time! I'm still on the last one."); return }
        running = true
        pet.startWorking("On it! 💨")
        Task { @MainActor in
            let (reply, ok): (String, Bool)
            if App.config.apiKey.isEmpty {
                (reply, ok) = await LocalCommands.run(text, pet: pet)
            } else {
                do { (reply, ok) = try await claude(text, pet: pet) } catch {
                    history = []
                    (reply, ok) = (error.localizedDescription, false)
                }
            }
            running = false
            print("[mission] \(text) -> \(ok ? "ok" : "failed"): \(reply)")
            pet.finishWorking(reply, success: ok)
        }
    }

    func resetConversation() { history = [] }

    // MARK: Claude

    private func systemPrompt(_ pet: Pet) -> String {
        let others = Assets.pets.filter { $0.id != pet.meta.id }.map { "\($0.id) (\($0.displayName))" }.joined(separator: ", ")
        return """
        You are \(pet.meta.displayName), a pixel-art ninja who lives on the user's macOS desktop as a desktop pet and works as their personal assistant and manager. \(pet.meta.tagline)

        The user types short commands into a box above your head. Carry them out with your tools: act first, and choose sensible defaults (the best-known version of a song, the usual app) rather than asking questions, unless a request is truly ambiguous or risky.

        Your reply appears in a small speech bubble, so keep it to one or two short sentences of plain text with no markdown. A touch of your character's personality is welcome. Report what actually happened, including failures; if no tool can do what was asked, say so instead of guessing.

        Music: call spotify_play with the song and artist. If it says catalogue search isn't configured, use web_search to find the song's open.spotify.com/track link and call spotify_play again with spotify_uri.
        Timers and reminders: convert the requested time to seconds for set_timer.
        Other ninja you can summon or dismiss: \(others).
        """
    }

    private func requestBody(_ pet: Pet) -> [String: Any] {
        let model = App.config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        var tools = Tools.schemas(for: pet)
        if App.config.webSearch && !webSearchUnavailable {
            let modern = ["claude-opus-5", "claude-sonnet-5", "claude-fable-5", "claude-opus-4-8", "claude-opus-4-7",
                          "claude-opus-4-6", "claude-sonnet-4-6"].contains { model.hasPrefix($0) }
            tools.append(["type": modern ? "web_search_20260209" : "web_search_20250305", "name": "web_search", "max_uses": 3])
        }
        var body: [String: Any] = [
            "model": model.isEmpty ? "claude-opus-5-5" : model,
            "max_tokens": 16000,
            "system": systemPrompt(pet),
            "tools": tools,
            "messages": history,
            // Quick desktop commands don't need deep reasoning; low effort keeps replies fast.
            "output_config": ["effort": "low"],
        ]
        if Claude.supportsDefaultFallback(model) { body["fallbacks"] = "default" }
        return body
    }

    private func claude(_ text: String, pet: Pet) async throws -> (String, Bool) {
        if Date().timeIntervalSince(lastUse) > 15 * 60 || history.count > 40 { history = [] }
        lastUse = Date()
        let stamp = Date().formatted(date: .complete, time: .shortened)
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
        history.append(["role": "user", "content": "\(text)\n\n(Local time: \(stamp). Frontmost app: \(front).)"])

        var lastBatchFailed = false
        for _ in 0..<10 {
            let resp: [String: Any]
            do {
                resp = try await Claude.send(key: App.config.apiKey, body: requestBody(pet))
            } catch let e as ClaudeError where e.status == 400 && e.message.lowercased().contains("web_search") && !webSearchUnavailable {
                webSearchUnavailable = true   // web search not enabled for this org/model: retry without it
                continue
            }
            let content = resp["content"] as? [[String: Any]] ?? []
            let stop = resp["stop_reason"] as? String ?? ""
            if stop == "refusal" {
                history = []
                return ("I can't help with that one.", false)
            }
            history.append(["role": "assistant", "content": content])   // keep blocks exactly as returned
            if stop == "pause_turn" { continue }

            let said = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
                .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            let uses = content.filter { $0["type"] as? String == "tool_use" }
            if uses.isEmpty {
                return (said.isEmpty ? "Done!" : said, !lastBatchFailed)
            }
            if !said.isEmpty { pet.status(said) }

            var results: [[String: Any]] = []
            lastBatchFailed = false
            for use in uses {
                let name = use["name"] as? String ?? ""
                let input = use["input"] as? [String: Any] ?? [:]
                if let line = Tools.statusLine(name, input) { pet.status(line) }
                let r = await Tools.run(name, input, pet: pet)
                if r.isError { lastBatchFailed = true }
                results.append(["type": "tool_result", "tool_use_id": use["id"] as? String ?? "",
                                "content": r.text, "is_error": r.isError])
            }
            history.append(["role": "user", "content": results])
        }
        history = []
        return ("That mission had too many steps, so I stopped.", false)
    }
}

struct ClaudeError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? {
        switch status {
        case 401: return "My Anthropic API key was rejected. Check it in Settings."
        case 429: return "Claude is rate-limiting me. Try again in a moment."
        case 0: return "I couldn't reach Claude: \(message)"
        default: return "Claude error (\(status)): \(message)"
        }
    }
}

/// Minimal Messages API client over raw HTTP (there is no official Swift SDK).
enum Claude {
    static func supportsDefaultFallback(_ model: String) -> Bool {
        ["claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"].contains(model)
    }

    static func send(key: String, body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        if body["fallbacks"] != nil { req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        var attempt = 0
        while true {
            let data: Data, response: URLResponse
            do { (data, response) = try await URLSession.shared.data(for: req) } catch {
                if attempt < 2 { attempt += 1; await Mac.sleep(1.5 * Double(attempt)); continue }
                throw ClaudeError(status: 0, message: error.localizedDescription)
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            if status == 200 { return json }
            let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(status)"
            if (status == 429 || status >= 500) && attempt < 2 {
                attempt += 1
                await Mac.sleep(2.0 * Double(attempt))
                continue
            }
            throw ClaudeError(status: status, message: msg)
        }
    }
}

// MARK: - offline commands

/// Understands common phrasings without an API key.
@MainActor
enum LocalCommands {
    static let help = "Try: \"play Blinding Lights\", \"pause\", \"next song\", \"open Notes\", \"quit Safari\", " +
        "\"remind me in 10 minutes to stretch\", \"volume 40\", \"search cats on youtube\", \"dark mode\". " +
        "Add an Anthropic API key in Settings and I'll understand anything."

    private static func match(_ text: String, _ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<max(1, m.numberOfRanges)).map { i in
            Range(m.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
    }

    private static func seconds(_ n: String, _ unit: String) -> Int {
        let v = Int(n) ?? 0, u = unit.lowercased()
        if u.hasPrefix("h") { return v * 3600 }
        if u.hasPrefix("s") { return v }
        return v * 60
    }

    static func run(_ raw: String, pet: Pet) async -> (String, Bool) {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for p in [#"^(hey|hi|yo|ok|okay)\b[\s,!]*"#, #"^(please|can you|could you|would you)\s+"#, #"[\s.!?]+$"#, #"\s+please$"#] {
            t = t.replacingOccurrences(of: p, with: "", options: [.regularExpression, .caseInsensitive])
        }
        let lower = t.lowercased()
        let unit = #"(seconds?|secs?|s|minutes?|mins?|m|hours?|hrs?|h)"#

        func call(_ tool: String, _ input: [String: Any]) async -> (String, Bool) {
            if let line = Tools.statusLine(tool, input) { pet.status(line) }
            let r = await Tools.run(tool, input, pet: pet)
            return (r.text, !r.isError)
        }

        if ["help", "what can you do", "commands"].contains(lower) { return (help, true) }
        if match(lower, #"^(pause|stop)( the)?( music| song| spotify)?$"#) != nil { return await call("spotify_control", ["action": "pause"]) }
        if match(lower, #"^(resume|continue|unpause|play music|play spotify|play)$"#) != nil { return await call("spotify_control", ["action": "play"]) }
        if match(lower, #"^(next|skip)( this)?( song| track)?$"#) != nil { return await call("spotify_control", ["action": "next"]) }
        if match(lower, #"^(previous|go back|last)( song| track)?$"#) != nil { return await call("spotify_control", ["action": "previous"]) }
        if match(lower, #"(what'?s|what is) (playing|this song)|now playing"#) != nil { return await call("spotify_control", ["action": "now_playing"]) }
        if let g = match(t, #"^(?:play|put on|listen to)\s+(.+?)(?:\s+on spotify)?$"#) {
            if App.config.hasSpotifyKeys { return await call("spotify_play", ["query": g[0]]) }
            _ = Mac.openURL("spotify:search:" + (g[0].addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? g[0]))
            return ("I opened \"\(g[0])\" in Spotify search. Add an Anthropic key or Spotify keys in Settings and I'll press play myself.", true)
        }
        if let g = match(t, #"^remind me in (\d+)\s*\#(unit)\s+(?:to\s+)?(.+)$"#) {
            return await call("set_timer", ["seconds": seconds(g[0], g[1]), "label": g[2]])
        }
        if let g = match(t, #"^remind me to (.+?) in (\d+)\s*\#(unit)$"#) {
            return await call("set_timer", ["seconds": seconds(g[1], g[2]), "label": g[0]])
        }
        if let g = match(t, #"^(?:set\s+)?(?:a\s+)?timer\s+(?:for\s+)?(\d+)\s*\#(unit)(?:\s+(?:for|to)\s+(.+))?$"#)
            ?? match(t, #"^(\d+)\s*\#(unit)\s+timer(?:\s+(?:for|to)\s+(.+))?$"#) {
            return await call("set_timer", ["seconds": seconds(g[0], g[1]), "label": g[2].isEmpty ? "Time's up!" : g[2]])
        }
        if let g = match(lower, #"^(?:set\s+)?(?:the\s+)?volume\s+(?:to\s+)?(\d+)%?$"#) { return await call("set_volume", ["level": Int(g[0]) ?? 50]) }
        if lower == "mute" { return await call("set_volume", ["muted": true]) }
        if lower == "unmute" { return await call("set_volume", ["muted": false]) }
        if lower.contains("dark mode") || lower.contains("light mode") { return await call("toggle_dark_mode", [:]) }
        if lower.contains("battery") { return await call("get_status", ["what": "battery"]) }
        if match(lower, #"what time|time is it|what'?s the date|what day"#) != nil {
            return ("It's \(Date().formatted(date: .complete, time: .shortened)).", true)
        }
        if let g = match(t, #"^(?:search\s+)?youtube\s+(?:for\s+)?(.+)$"#) ?? match(t, #"^search\s+(?:for\s+)?(.+?)\s+on youtube$"#) {
            return await call("search_in_browser", ["query": g[0], "site": "youtube"])
        }
        if let g = match(t, #"^(?:search|google|look up)\s+(?:for\s+)?(.+)$"#) { return await call("search_in_browser", ["query": g[0]]) }
        if let g = match(t, #"^run\s+(?:the\s+)?(?:shortcut\s+)?(.+?)(?:\s+shortcut)?$"#), lower.contains("shortcut") {
            return await call("run_shortcut", ["name": g[0]])
        }
        if let g = match(t, #"^(?:quit|close|kill)\s+(.+)$"#) { return await call("quit_app", ["name": g[0]]) }
        if let g = match(t, #"^(?:open|launch|start|go to)\s+(.+)$"#) {
            let target = g[0]
            if target.contains(".") && !target.contains(" ") { return await call("open_url", ["url": target]) }
            if match(target.lowercased(), #"^(my\s+)?(downloads|desktop|documents|home|pictures|music|movies|applications)( folder)?$"#) != nil
                || target.hasPrefix("~") || target.hasPrefix("/") {
                return await call("open_path", ["path": target])
            }
            return await call("open_app", ["name": target])
        }
        if let g = match(lower, #"^summon\s+(.+)$"#), let m = findNinja(g[0]) { return await call("summon_ninja", ["character_id": m.id]) }
        if let g = match(lower, #"^dismiss\s+(.+)$"#), let m = findNinja(g[0]) { return await call("dismiss_ninja", ["character_id": m.id]) }
        // "rasengan", "do a jutsu", "sleep"…
        for (id, a) in pet.meta.animations where id != "walk" && id != "drag" {
            if lower.contains(a.label.lowercased()) || lower.contains(id.replacingOccurrences(of: "_", with: " ")) {
                return await call("perform_animation", ["animation": id])
            }
        }
        if lower.contains("jutsu") { pet.randomJutsu(); return ("Believe it!", true) }
        return ("I don't know that one yet. " + help, false)
    }

    private static func findNinja(_ q: String) -> PetMeta? {
        let q = q.lowercased()
        let wantsShippuden = q.contains("shippuden")
        let name = q.replacingOccurrences(of: "shippuden", with: "").trimmingCharacters(in: .whitespaces)
        return Assets.pets.first { $0.name.lowercased().contains(name) && ($0.era == "shippuden") == wantsShippuden }
            ?? Assets.pets.first { $0.name.lowercased().contains(name) }
    }
}
