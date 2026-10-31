import AppKit

/// Turns a typed command into actions.
/// 1. The offline parser handles common phrasings instantly with no model at all.
/// 2. Anything else goes to Apple's on-device model (Apple Intelligence). macOS loads and
///    unloads that model itself, so it adds almost nothing to this app's memory.
@MainActor
final class Agent {
    static let shared = Agent()
    private(set) var running = false

    func handle(_ text: String, pet: Pet) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !running else { pet.say("One mission at a time! I'm still on the last one."); return }
        running = true
        pet.startWorking("On it! 💨")
        Task { @MainActor in
            var result = await LocalCommands.run(text, pet: pet)
            #if canImport(FoundationModels)
            if result == nil, #available(macOS 26.0, *), AIAvailability.available {
                result = await OnDeviceAI.shared.run(text, pet: pet)
            }
            #endif
            if result == nil {
                result = ("I don't know that one. \(AIAvailability.hint) " + LocalCommands.help, false)
            }
            let (reply, ok) = result!
            running = false
            print("[mission] \(text) -> \(ok ? "ok" : "failed"): \(reply)")
            pet.finishWorking(reply, success: ok)
        }
    }

    /// Called when the command box opens so the model is loaded by the time you press Return.
    func prewarm(_ pet: Pet) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), AIAvailability.available { OnDeviceAI.shared.prewarm(pet) }
        #endif
    }

    static var statusText: String {
        AIAvailability.available ? "AI: Apple Intelligence (on-device)" : "AI: simple commands only"
    }
}

// MARK: - offline commands

/// Understands common phrasings with plain pattern matching. Returns nil when it doesn't recognise the command.
@MainActor
enum LocalCommands {
    static let help = "Try: \"play Blinding Lights\", \"pause\", \"next song\", \"open Notes\", \"quit Safari\", " +
        "\"remind me in 10 minutes to stretch\", \"volume 40\", \"search cats on youtube\", \"dark mode\"."

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

    static func run(_ raw: String, pet: Pet) async -> (String, Bool)? {
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
        if let g = match(t, #"^(?:play|put on|listen to)\s+(?:the\s+)?(?:song\s+)?(.+?)(?:\s+on spotify)?$"#),
           match(g[0].lowercased(), #"^(something|some|anything|a song|music)\b"#) == nil {   // vague requests go to the model
            return await call("spotify_play", ["query": g[0]])
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
        if match(lower, #"^(toggle |switch to |turn on |turn off )?(dark|light) mode$"#) != nil { return await call("toggle_dark_mode", [:]) }
        if match(lower, #"^(battery|battery level|how much battery|what'?s my battery)"#) != nil { return await call("get_status", ["what": "battery"]) }
        if match(lower, #"^(what time is it|what'?s the time|time|what'?s the date|what day is it)$"#) != nil {
            return ("It's \(Date().formatted(date: .complete, time: .shortened)).", true)
        }
        if let g = match(t, #"^(?:search\s+)?youtube\s+(?:for\s+)?(.+)$"#) ?? match(t, #"^search\s+(?:for\s+)?(.+?)\s+on youtube$"#) {
            return await call("search_in_browser", ["query": g[0], "site": "youtube"])
        }
        if let g = match(t, #"^(?:search|google|look up)\s+(?:for\s+)?(.+)$"#) { return await call("search_in_browser", ["query": g[0]]) }
        if let g = match(t, #"^run\s+(?:the\s+|my\s+)?(?:shortcut\s+)?(.+?)(?:\s+shortcut)?$"#), lower.contains("shortcut") {
            return await call("run_shortcut", ["name": g[0]])
        }
        if let g = match(t, #"^(?:quit|close|kill)\s+([\w .+-]{1,40})$"#), Mac.runningApp(g[0]) != nil {
            return await call("quit_app", ["name": g[0]])
        }
        if let g = match(t, #"^(?:open|launch|start|go to)\s+(.+)$"#) {
            let target = g[0]
            if target.contains(".") && !target.contains(" ") { return await call("open_url", ["url": target]) }
            if match(target.lowercased(), #"^(my\s+)?(downloads|desktop|documents|home|pictures|music|movies|applications)( folder)?$"#) != nil
                || target.hasPrefix("~") || target.hasPrefix("/") {
                return await call("open_path", ["path": target])
            }
            if Mac.findApp(target) != nil { return await call("open_app", ["name": target]) }
        }
        if let g = match(lower, #"^summon\s+(.+)$"#), let m = findNinja(g[0]) { return await call("summon_ninja", ["character_id": m.id]) }
        if let g = match(lower, #"^dismiss\s+(.+)$"#), let m = findNinja(g[0]) { return await call("dismiss_ninja", ["character_id": m.id]) }
        // "rasengan", "sleep", "do a rasengan"…
        for (id, a) in pet.meta.animations where id != "walk" && id != "drag" {
            let label = a.label.lowercased(), plain = id.replacingOccurrences(of: "_", with: " ")
            if [label, plain, "do " + label, "do a " + label, "do " + plain, "do a " + plain].contains(lower) {
                return await call("perform_animation", ["animation": id])
            }
        }
        if match(lower, #"^(do )?(a |your )?(random )?jutsu$"#) != nil { pet.randomJutsu(); return ("Believe it!", true) }
        return nil
    }

    static func findNinja(_ q: String) -> PetMeta? {
        let q = q.lowercased()
        let wantsShippuden = q.contains("shippuden")
        let name = q.replacingOccurrences(of: "shippuden", with: "").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return Assets.pets.first { $0.name.lowercased().contains(name) && ($0.era == "shippuden") == wantsShippuden }
            ?? Assets.pets.first { $0.name.lowercased().contains(name) }
    }
}
