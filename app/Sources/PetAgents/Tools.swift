import AppKit

/// Everything the pet can do for you. Used by the on-device model (as tools) and by the offline command parser.
enum Tools {
    private static func tool(_ name: String, _ description: String, _ props: [String: Any] = [:],
                             required: [String] = []) -> [String: Any] {
        ["name": name, "description": description,
         "input_schema": ["type": "object", "properties": props, "required": required] as [String: Any]]
    }
    private static func str(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
    private static func oneOf(_ values: [String], _ d: String) -> [String: Any] { ["type": "string", "enum": values, "description": d] }

    static func schemas(for pet: Pet) -> [[String: Any]] {
        let anims = pet.meta.animations.keys.filter { $0 != "walk" && $0 != "drag" }.sorted()
        return [
            tool("open_app", "Open (launch and bring to front) a macOS application by name, e.g. Spotify, Safari, Notes, Visual Studio Code.",
                 ["name": str("Application name")], required: ["name"]),
            tool("quit_app", "Quit a running macOS application.", ["name": str("Application name")], required: ["name"]),
            tool("spotify_play", "Play a song, album, playlist or artist in the Spotify app.",
                 ["query": str("Song and artist, e.g. 'Blinding Lights The Weeknd'"),
                  "kind": oneOf(["track", "album", "playlist", "artist"], "What the query names. Default track."),
                  "spotify_uri": str("Only if the user gave a Spotify link")]),
            tool("spotify_control", "Control Spotify playback or ask what is playing.",
                 ["action": oneOf(["play", "pause", "toggle", "next", "previous", "now_playing", "shuffle_on", "shuffle_off"], "Action")],
                 required: ["action"]),
            tool("set_volume", "Change the Mac's output volume or mute it. Use change for 'a bit louder/quieter' (about 10-15).",
                 ["level": ["type": "integer", "description": "Absolute volume 0-100"],
                  "change": ["type": "integer", "description": "Relative change, e.g. -10 to turn it down a bit"],
                  "muted": ["type": "boolean", "description": "true to mute, false to unmute"]]),
            tool("open_url", "Open a web page or link, in the default browser or in a given app.",
                 ["url": str("Full URL"), "app": str("Optional browser/app, e.g. Safari")], required: ["url"]),
            tool("type_text", "Type text into an app as if the user typed it: opens or focuses the app, pastes the text, " +
                 "and presses Return when submit is true. Use it for 'type X in Claude', 'ask ChatGPT X', 'write X in Notes'.",
                 ["app": str("App to type into, e.g. Claude, Notes. Empty = the app in front"),
                  "text": str("Exact text to type"),
                  "submit": ["type": "boolean", "description": "Press Return afterwards to send it. Defaults to true for AI chat apps " +
                             "(Claude, ChatGPT, Perplexity, Gemini); set false only if the user says not to send"],
                  "compose": ["type": "boolean", "description": "true when text is a request for you to write something " +
                              "(e.g. 'a haiku about rain', 'an email asking for leave'): you write it first, then type it"]],
                 required: ["text"]),
            tool("press_keys", "Press keyboard shortcuts in an app, e.g. cmd+n for a new chat/window, cmd+t new tab, cmd+w close tab.",
                 ["app": str("App to press them in. Empty = the app in front"),
                  "keys": str("Comma-separated combos, e.g. 'cmd+n' or 'cmd+l, return'")], required: ["keys"]),
            tool("launch_game", "Launch an installed game (Steam library or Applications).", ["name": str("Game name")],
                 required: ["name"]),
            tool("search_in_browser", "Open a Google or YouTube search results page in the browser for the user to look at.",
                 ["query": str("Search terms"), "site": oneOf(["google", "youtube"], "Default google")], required: ["query"]),
            tool("open_path", "Open a folder or file in Finder / its default app. Accepts ~ paths or names like downloads, desktop, documents.",
                 ["path": str("Path or folder name")], required: ["path"]),
            tool("set_timer", "Start a timer or reminder. When it fires, the pet announces the label with a sound.",
                 ["seconds": ["type": "integer", "minimum": 1, "description": "Delay in seconds"],
                  "label": str("What to remind the user about")], required: ["seconds", "label"]),
            tool("run_shortcut", "Run one of the user's Apple Shortcuts by its exact name.", ["name": str("Shortcut name")], required: ["name"]),
            tool("toggle_dark_mode", "Switch macOS to dark or light appearance.",
                 ["mode": oneOf(["dark", "light", "toggle"], "Default toggle")]),
            tool("get_status", "Read Mac status: battery level, the frontmost app, or the song playing in Spotify.",
                 ["what": oneOf(["battery", "frontmost_app", "now_playing"], "What to read")], required: ["what"]),
            tool("perform_animation", "Make yourself (the pet) perform one of your animations, e.g. a jutsu, for fun.",
                 ["animation": oneOf(anims, "Animation id")], required: ["animation"]),
            tool("summon_pet", "Bring another pet character onto the desktop.",
                 ["name": str("Character name, e.g. Sasuke, Venom, Miles Morales")], required: ["name"]),
            tool("dismiss_pet", "Send a pet character away from the desktop.",
                 ["name": str("Character name")], required: ["name"]),
        ]
    }

    /// Short status line shown in the speech bubble while a tool runs.
    static func statusLine(_ name: String, _ input: [String: Any]) -> String? {
        let s = { (k: String) in input[k] as? String ?? "" }
        switch name {
        case "open_app": return "Opening \(s("name"))…"
        case "quit_app": return "Closing \(s("name"))…"
        case "spotify_play": return "🎵 Finding \(s("query").isEmpty ? "that" : s("query"))…"
        case "type_text": return "⌨️ Typing in \(s("app").isEmpty ? "the app" : s("app"))…"
        case "launch_game": return "🎮 Starting \(s("name"))…"
        case "web_search": return "🔎 Looking it up…"
        case "open_url", "search_in_browser": return "Opening the browser…"
        case "set_timer": return "⏰ Setting a timer…"
        case "run_shortcut": return "Running \(s("name"))…"
        default: return nil
        }
    }

    @MainActor
    static func run(_ name: String, _ input: [String: Any], pet: Pet) async -> ActionResult {
        let s = { (k: String) -> String in (input[k] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        let i = { (k: String) -> Int? in (input[k] as? NSNumber)?.intValue }
        // PETAGENTS_DRYRUN=1: log what would happen instead of doing it (for testing).
        if ProcessInfo.processInfo.environment["PETAGENTS_DRYRUN"] == "1" {
            var extra = ""
            if name == "launch_game" { extra = " → \(Steam.find(s("name"))?.name ?? "not installed")" }
            print("[dry-run] \(name) \(input)\(extra)")
            return .ok("Done (dry run).")
        }
        switch name {
        case "open_app":
            return s("name").isEmpty ? .fail("Missing name.") : await Mac.openApp(s("name"))
        case "quit_app":
            return s("name").isEmpty ? .fail("Missing name.") : Mac.quitApp(s("name"))
        case "spotify_play":
            return await spotifyPlay(query: s("query"), kind: s("kind").isEmpty ? "track" : s("kind"), uri: s("spotify_uri"))
        case "spotify_control":
            return await Spotify.control(s("action"))
        case "set_volume":
            var level = i("level")
            if level == nil, let change = i("change") { level = await Mac.currentVolume() + change }
            return await Mac.setVolume(level: level, muted: input["muted"] as? Bool)
        case "open_url":
            return await Mac.openURL(s("url"), in: s("app"))
        case "type_text":
            var text = input["text"] as? String ?? ""
            if input["compose"] as? Bool == true {
                pet.status("✍️ Writing it…")
                guard let written = await Composer.write(text) else {
                    return .fail("I can't write text without Apple Intelligence.")
                }
                text = written
            }
            if input["new_chat"] as? Bool == true, !s("app").isEmpty {
                let r = await pressKeys(app: s("app"), keys: "cmd+n")
                if r.isError { return r }
                await Mac.sleep(0.8)
            }
            let isAssistant = LocalCommands.chatAssistants.contains(s("app").lowercased().replacingOccurrences(of: " ", with: ""))
            return await typeText(app: s("app"), text: text, submit: input["submit"] as? Bool ?? isAssistant)
        case "press_keys":
            return await pressKeys(app: s("app"), keys: s("keys"))
        case "launch_game":
            if let app = Mac.findApp(s("name")), !s("name").isEmpty, Steam.find(s("name")) == nil {
                return await Mac.openApp(app.deletingPathExtension().lastPathComponent)
            }
            return Steam.launch(s("name"))
        case "search_in_browser":
            return Mac.searchWeb(s("query"), site: s("site").isEmpty ? "google" : s("site"))
        case "open_path":
            return Mac.openPath(s("path"))
        case "set_timer":
            guard let secs = i("seconds"), secs > 0 else { return .fail("seconds must be a positive integer.") }
            Timers.start(seconds: secs, label: s("label").isEmpty ? "Time's up!" : s("label"), pet: pet)
            return .ok("Timer set for \(Timers.describe(secs)).")
        case "run_shortcut":
            return await Mac.runShortcut(s("name"))
        case "toggle_dark_mode":
            return await Mac.setAppearance(s("mode").isEmpty ? "toggle" : s("mode"))
        case "get_status":
            switch s("what") {
            case "battery": return .ok(await Mac.battery())
            case "frontmost_app": return .ok(NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown")
            default: return await Spotify.control("now_playing")
            }
        case "perform_animation":
            let id = s("animation")
            guard pet.meta.animations[id] != nil else { return .fail("No animation \(id).") }
            pet.play(id)
            return .ok("Performing \(pet.meta.animations[id]!.label).")
        case "summon_pet", "summon_ninja":
            guard let m = Assets.byId[s("character_id")] ?? LocalCommands.findNinja(s("name")) else {
                return .fail("I don't know a character called \(s("name")).")
            }
            App.delegate.summon(m.id)
            return .ok("\(m.displayName) has arrived.")
        case "dismiss_pet", "dismiss_ninja":
            guard let m = Assets.byId[s("character_id")] ?? LocalCommands.findNinja(s("name")) else {
                return .fail("I don't know a character called \(s("name")).")
            }
            if m.id == pet.meta.id { return .fail("I can't dismiss myself while working on your mission.") }
            App.delegate.dismiss(m.id)
            return .ok("\(m.displayName) left.")
        default:
            return .fail("Unknown tool \(name).")
        }
    }

    /// Web versions of chat assistants, used when their desktop app isn't installed.
    private static let webAssistants: [String: String] = [
        "claude": "https://claude.ai/new?q=", "chatgpt": "https://chatgpt.com/?q=",
        "perplexity": "https://www.perplexity.ai/search?q=",
    ]

    static func typeText(app: String, text: String, submit: Bool) async -> ActionResult {
        guard !text.isEmpty else { return .fail("Nothing to type.") }
        let key = app.lowercased().replacingOccurrences(of: " ", with: "")
        if !app.isEmpty, Mac.findApp(app) == nil, let web = webAssistants[key] {
            let q = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
            return Mac.openURL(web + q)
        }
        guard Keyboard.allowed(prompt: true) else { return .fail(Keyboard.permissionMessage) }
        if app.isEmpty { await Mac.sleep(0.5) }          // let focus go back to the app you were using
        else if let err = await Keyboard.focus(app: app) { return err }
        await Keyboard.paste(text)
        if submit { await Mac.sleep(0.25); _ = Keyboard.press("return") }
        let target = app.isEmpty ? (NSWorkspace.shared.frontmostApplication?.localizedName ?? "the front app") : app
        return .ok(submit ? "Sent it in \(target)." : "Typed it into \(target).")
    }

    static func pressKeys(app: String, keys: String) async -> ActionResult {
        guard Keyboard.allowed(prompt: true) else { return .fail(Keyboard.permissionMessage) }
        if app.isEmpty { await Mac.sleep(0.5) } else if let err = await Keyboard.focus(app: app) { return err }
        let combos = keys.replacingOccurrences(of: " then ", with: ",").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for c in combos {
            guard Keyboard.press(c) else { return .fail("I don't know the key \(c).") }
            await Mac.sleep(0.3)
        }
        return .ok("Pressed \(combos.joined(separator: ", ")).")
    }

    private static func spotifyPlay(query: String, kind: String, uri: String) async -> ActionResult {
        if !uri.isEmpty {
            guard let u = Spotify.normalize(uri) else { return .fail("Not a Spotify link: \(uri)") }
            return await Spotify.play(uri: u, label: query.isEmpty ? "it" : query)
        }
        guard !query.isEmpty else { return .fail("Give a query or spotify_uri.") }
        if App.config.hasSpotifyKeys {
            do {
                if let (u, label) = try await Spotify.search(query, kind: kind) {
                    return await Spotify.play(uri: u, label: label)
                }
                return .fail("Spotify found nothing for \(query).")
            } catch {
                return .fail("Spotify search failed: \(error.localizedDescription)")
            }
        }
        // No Spotify keys: open Spotify's own search so the user is one click away.
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: Spotify.bundleID) != nil else {
            return .fail("Spotify isn't installed.")
        }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
        _ = Mac.openURL("spotify:search:" + encoded)
        return .ok("Opened Spotify search for \(query); the user needs to press play on the top result " +
                   "(adding Spotify keys in Settings lets me play it directly).")
    }
}

// MARK: - timers

enum Timers {
    static func describe(_ secs: Int) -> String {
        if secs < 60 { return "\(secs) second\(secs == 1 ? "" : "s")" }
        if secs < 3600 { let m = secs / 60, r = secs % 60; return "\(m) min" + (r > 0 ? " \(r) s" : "") }
        let h = secs / 3600, m = (secs % 3600) / 60
        return "\(h) h" + (m > 0 ? " \(m) min" : "")
    }

    @MainActor
    static func start(seconds: Int, label: String, pet: Pet) {
        let id = pet.meta.id
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) {
            let target = App.delegate.pet(id) ?? App.delegate.anyPet()
            NSSound(named: "Glass")?.play()
            target?.say("⏰ \(label)", seconds: 20)
            target?.randomJutsu()
        }
    }
}
