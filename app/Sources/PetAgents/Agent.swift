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
        let devanagari = Hindi.hasDevanagari(text)
        pet.startWorking(devanagari ? "अभी करता हूँ! 💨" : "On it! 💨")
        Task { @MainActor in
            let (reply, ok) = await solve(text, devanagari: devanagari, pet: pet)
            var shown = reply
            if devanagari, let hi = await Hindi.translate(reply, toHindi: true) { shown = hi }
            running = false
            print("[mission] \(text) -> \(ok ? "ok" : "failed"): \(shown)")
            HomeModel.shared.record(text, reply: shown, ok: ok, pet: pet.meta.shortName)
            pet.finishWorking(shown, success: ok)
        }
    }

    private func solve(_ text: String, devanagari: Bool, pet: Pet) async -> (String, Bool) {
        // 1. Hindi / Hinglish → English command, then the instant parser.
        let command = Hindi.toEnglishCommand(text) ?? text
        if command != text { print("[hindi] \(text) -> \(command)") }
        if let r = await LocalCommands.run(command, pet: pet) { return r }

        // 2. Devanagari the rules didn't cover: translate on-device, then parser / model.
        var forModel = command
        if devanagari {
            guard let english = await Hindi.translate(text, toHindi: false) else {
                return ("मैं अभी आसान हिंदी कमांड समझता हूँ। बाकी के लिए Home → Settings में Hindi डाउनलोड करें।", false)
            }
            print("[translate] \(text) -> \(english)")
            if let r = await LocalCommands.run(Hindi.toEnglishCommand(english) ?? english, pet: pet) { return r }
            forModel = english
        }

        // 3. Apple's on-device model.
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), AIAvailability.available {
            return await OnDeviceAI.shared.run(forModel, pet: pet)
        }
        #endif
        return ("I don't know that one. \(AIAvailability.hint) " + LocalCommands.help, false)
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
        // "send it" / "send": the message typed earlier (WhatsApp or another app) goes out now.
        if match(lower, #"^(?:ok(?:ay)?\s+)?(?:now\s+)?(?:send|send it|send that|send the message|send message|go ahead and send(?: it)?|yes send(?: it)?)(?:\s+now)?$"#) != nil {
            return await call("send_pending", [:])
        }
        // WhatsApp: open a chat, write in it, send only when told to.
        if lower.contains("whatsapp") {
            let wa = #"\s+(?:on|in|via|over|using)\s+whatsapp"#
            if let g = match(t, #"^send\s+["“']?(.+?)["”']?\s+to\s+(.+?)"# + wa + "$") {
                return await call("whatsapp_message", ["chat": g[1], "text": g[0], "send": true])
            }
            if let g = match(t, #"^(?:type|write|draft|put)\s+["“']?(.+?)["”']?\s+(?:to|for|in)\s+(.+?)(?:'s\s+chat|\s+chat)?"# + wa + #"(\s+and\s+send(?:\s+it)?)?$"#) {
                return await call("whatsapp_message", ["chat": g[1], "text": g[0], "send": !g[2].isEmpty])
            }
            if let g = match(t, #"^(?:message|msg|text|whatsapp)\s+(.+?)(?:"# + wa + #")?\s*(?:saying|that|:|,)\s*["“']?(.+?)["”']?(\s+and\s+send(?:\s+it)?)?$"#) {
                return await call("whatsapp_message", ["chat": g[0], "text": g[1], "send": !g[2].isEmpty])
            }
            if let g = match(t, #"^(?:open|search|search for|find|go to|show)\s+(?:my\s+)?(?:whatsapp\s+)?chat\s+(?:with|of|for)\s+(.+?)(?:"# + wa + ")?$")
                ?? match(t, #"^(?:open|search|search for|find)\s+(.+?)"# + wa + "$") {
                return await call("whatsapp_message", ["chat": g[0]])
            }
        }
        // "send hello to claude", "tell chatgpt I'm back", "send this to claude: …\"
        let ai = #"(claude|chatgpt|chat gpt|perplexity|gemini|copilot)"#
        if let g = match(t, #"^(?:send|message)\s+["“']?(.+?)["”']?\s+to\s+"# + ai + #"$"#)
            ?? match(t, #"^(?:send|tell|message)\s+"# + ai + #"[:,]?\s+(?:that\s+)?(.+)$"#).map({ [$0[1], $0[0]] }) {
            return await call("type_text", ["app": g[1].replacingOccurrences(of: " ", with: ""), "text": g[0], "submit": true])
        }
        // Typing into apps: "type hello in claude", "in notes write buy milk", "ask claude how to cook rice"
        if let g = match(t, #"^ask\s+(claude|chatgpt|chat gpt|perplexity|gemini|copilot)\s+(?:to\s+|about\s+|if\s+|whether\s+)?(for\s+)?(.+)$"#) {
            let text = g[1].isEmpty ? g[2] : "Give me " + g[2]        // "ask claude for a joke" → "Give me a joke"
            return await call("type_text", ["app": g[0].replacingOccurrences(of: " ", with: ""), "text": text,
                                            "submit": Self.shouldSend(g[0], explicit: true, t)])
        }
        // "open (a new chat in) claude and ask (it) for X"
        if let g = match(t, #"^(?:open\s+)?(a\s+)?(new\s+chat\s+(?:in|on)\s+)?(claude|chatgpt|chat gpt|perplexity)\s+and\s+ask\s+(?:it\s+)?(?:for\s+|to\s+|about\s+)?(.+)$"#) {
            return await call("type_text", ["app": g[2].replacingOccurrences(of: " ", with: ""), "text": g[3], "submit": true,
                                            "new_chat": !g[1].isEmpty])
        }
        let typed = t.replacingOccurrences(of: #",?\s+(?:but\s+)?(?:don'?t|do not)\s+send(?:\s+it)?$"#, with: "", options: [.regularExpression, .caseInsensitive])
        if let g = match(typed, #"^(?:type|write|paste|enter)\s+["“']?(.+?)["”']?\s+(?:in|into|on)\s+(?:the\s+)?([\w .+-]{2,30}?)(?:\s+app)?(\s+and\s+(?:send|submit|enter|press enter|hit enter)(?:\s+it)?)?$"#),
           Mac.findApp(g[1]) != nil || ["claude", "chatgpt", "perplexity"].contains(g[1].lowercased()) {
            return await call("type_text", ["app": g[1], "text": g[0], "submit": Self.shouldSend(g[1], explicit: !g[2].isEmpty, t),
                                            "compose": Self.isWritingRequest(g[0])])
        }
        if let g = match(typed, #"^(?:in|on)\s+([\w .+-]{2,30}?),?\s+(?:type|write)\s+["“']?(.+?)["”']?(\s+and\s+(?:send|submit|enter)(?:\s+it)?)?$"#),
           Mac.findApp(g[0]) != nil {
            return await call("type_text", ["app": g[0], "text": g[1], "submit": Self.shouldSend(g[0], explicit: !g[2].isEmpty, t),
                                            "compose": Self.isWritingRequest(g[1])])
        }
        if let g = match(t, #"^type\s+["“']?(.+?)["”']?$"#) { return await call("type_text", ["app": "", "text": g[0]]) }
        if let g = match(t, #"^open\s+(\S+\.\S+)\s+(?:in|with|on)\s+([\w .]+)$"#) {
            return await call("open_url", ["url": g[0], "app": g[1]])
        }
        // Games: "play arkham city on steam", "launch cs2", "open batman"
        if let g = match(t, #"^(?:play|launch|start|open|run)\s+(.+?)\s+(?:on|in|from|via|using)\s+steam$"#) {
            return await call("launch_game", ["name": g[0]])
        }
        if let g = match(t, #"^(?:play|launch|start|open|run)\s+(?:the\s+)?(?:game\s+)?(.+?)(?:\s+game)?$"#), Steam.find(g[0]) != nil {
            return await call("launch_game", ["name": g[0]])
        }
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
        // Apple Reminders: "remind me to call mom tomorrow at 5", "add buy milk to my reminders"
        if let g = match(t, #"^(?:add|create|make|set)\s+(?:a\s+)?reminder\s+(?:to\s+|for\s+|that\s+|about\s+)?(.+)$"#)
            ?? match(t, #"^add\s+(.+?)\s+to\s+(?:my\s+)?(?:reminders|to-?do(?: list)?|todos)$"#)
            ?? match(t, #"^remind me (?:to|about|of)\s+(.+)$"#) {
            return await call("add_reminder", ["title": g[0]])
        }
        if let g = match(lower, #"^(?:what are|show|show me|list|read|check)\s+(?:my\s+)?(?:reminders|to-?dos?|to-?do list)(\s+(?:for\s+)?today)?$"#)
            ?? match(lower, #"^(?:my\s+)?reminders(\s+today)?$"#) {
            return await call("list_reminders", ["scope": g[0].isEmpty ? "all" : "today"])
        }
        // Calendar: "schedule dentist friday at 3pm", "add standup tomorrow at 9 to my calendar"
        if let g = match(t, #"^(?:add|put|create)\s+(?:an?\s+)?(.+?)\s+(?:to|in|on)\s+(?:my\s+)?calendar$"#)
            ?? match(t, #"^(?:schedule|book|set up|plan)\s+(?:an?\s+)?(.+)$"#)
            ?? match(t, #"^(?:add|create)\s+(?:an?\s+)?((?:event|meeting|appointment|call)\s+.+)$"#),
           When.parse(g[0]) != nil {
            return await call("add_calendar_event", ["title": g[0], "when": ""])
        }
        if let g = match(lower, #"^(?:what'?s|what is|show|show me|check|read)\s+(?:on\s+)?(?:my\s+)?(?:calendar|schedule|agenda|events|meetings)(?:\s+(?:for\s+|on\s+)?(.+))?$"#)
            ?? match(lower, #"^(?:what|which|any)\s+(?:meetings|events)\s+(?:do i have\s+)?(.+)?$"#)
            ?? match(lower, #"^do i have (?:any\s+)?(?:meetings|events)(?:\s+(.+))?$"#) {
            return await call("list_calendar_events", ["day": g[0].isEmpty ? "today" : g[0]])
        }
        if let g = match(lower, #"^(?:set\s+)?(?:the\s+)?volume\s+(?:to\s+)?(\d+)%?$"#) { return await call("set_volume", ["level": Int(g[0]) ?? 50]) }
        if lower == "mute" { return await call("set_volume", ["muted": true]) }
        if lower == "unmute" { return await call("set_volume", ["muted": false]) }
        if let g = match(lower, #"^(?:toggle |switch to |turn on |enable |go )?(dark|light) mode(?: on)?$"#) {
            return await call("toggle_dark_mode", ["mode": g[0]])
        }
        if match(lower, #"^(volume up|louder|turn it up|turn up the volume|increase (the )?volume)$"#) != nil {
            return await call("set_volume", ["change": 15])
        }
        if match(lower, #"^(volume down|quieter|turn it down|turn down the volume|lower the volume|decrease (the )?volume)$"#) != nil {
            return await call("set_volume", ["change": -15])
        }
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
            if let site = Self.sites[target.lowercased()] { return await call("open_url", ["url": site]) }
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
        if match(lower, #"^(do )?(a |your )?(random )?(jutsu|move|trick)$"#) != nil { pet.randomJutsu(); return ("Believe it!", true) }
        // Someone else's move ("do a web swing" asked of Naruto): say who can do it.
        let wanted = lower.replacingOccurrences(of: #"^(?:do|use|show me)\s+(?:a\s+|an\s+|the\s+|your\s+)?"#, with: "",
                                                options: .regularExpression)
        if wanted != lower, let other = Assets.pets.first(where: { m in
            m.animations.contains { id, a in a.kind != "base" && (a.label.lowercased() == wanted || id.replacingOccurrences(of: "_", with: " ") == wanted) }
        }) {
            return ("That's \(other.name)'s move! Say \"summon \(other.name)\" and ask them.", false)
        }
        return nil
    }

    static let sites: [String: String] = [
        "youtube": "https://www.youtube.com", "google": "https://www.google.com", "gmail": "https://mail.google.com",
        "github": "https://github.com", "instagram": "https://www.instagram.com", "facebook": "https://www.facebook.com",
        "twitter": "https://x.com", "x": "https://x.com", "linkedin": "https://www.linkedin.com",
        "netflix": "https://www.netflix.com", "chatgpt": "https://chatgpt.com", "amazon": "https://www.amazon.in",
        "flipkart": "https://www.flipkart.com", "hotstar": "https://www.hotstar.com", "whatsapp": "https://web.whatsapp.com",
        "यूट्यूब": "https://www.youtube.com", "गूगल": "https://www.google.com",
    ]

    /// AI chat apps get the message sent (Return pressed) unless the user says not to; other apps only get it typed.
    static let chatAssistants: Set<String> = ["claude", "chatgpt", "perplexity", "gemini", "copilot"]

    static func shouldSend(_ app: String, explicit: Bool, _ command: String) -> Bool {
        if match(command.lowercased(), #"(?:don'?t|do not|without|but not|no)\s+(?:send|sending|submit|enter)|bina\s+bheje|मत\s+भेजो|mat\s+bhejo"#) != nil {
            return false
        }
        return explicit || chatAssistants.contains(app.lowercased().replacingOccurrences(of: " ", with: ""))
    }

    /// "a haiku about rain", "an email to my boss…" ask the pet to write something, not to type those words.
    static func isWritingRequest(_ text: String) -> Bool {
        match(text.lowercased(), #"^(?:me\s+)?(?:a|an|some|two|three|short|quick)\s+(?:\w+\s+){0,2}(?:haiku|poem|email|mail|story|joke|note|message|paragraph|summary|letter|reply|tweet|list|essay|caption|bio|song|limerick|description)s?\b"#) != nil
    }

    private static let nicknames: [String: String] = [
        "spiderman": "spider_man", "peter": "spider_man", "peterparker": "spider_man", "spidey": "spider_man",
        "miles": "miles_morales", "spiderwoman": "spider_gwen", "gwen": "spider_gwen", "ghostspider": "spider_gwen",
        "spidergwen": "spider_gwen", "docock": "doc_ock", "doctoroctopus": "doc_ock", "octopus": "doc_ock",
        "ock": "doc_ock", "goblin": "green_goblin", "greengoblin": "green_goblin", "normanosborn": "green_goblin",
        "eddie": "venom", "eddiebrock": "venom",
    ]

    static func findNinja(_ raw: String) -> PetMeta? {
        let q = raw.lowercased().replacingOccurrences(of: #"^(the|mr\.?|dr\.?)\s+"#, with: "", options: .regularExpression)
        let key = q.filter { $0.isLetter }
        if let id = nicknames[key], let m = Assets.byId[id] { return m }
        if let m = Assets.pets.first(where: { $0.name.lowercased().filter(\.isLetter) == key }) { return m }
        let wantsShippuden = q.contains("shippuden")
        let name = q.replacingOccurrences(of: "shippuden", with: "").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return Assets.pets.first { $0.name.lowercased().contains(name) && ($0.era == "shippuden") == wantsShippuden }
            ?? Assets.pets.first { $0.name.lowercased().contains(name) }
    }
}
