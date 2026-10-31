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
            tool("open_url", "Open a web page or link in the default browser.", ["url": str("Full URL")], required: ["url"]),
            tool("search_in_browser", "Open a Google or YouTube search results page in the browser for the user to look at.",
                 ["query": str("Search terms"), "site": oneOf(["google", "youtube"], "Default google")], required: ["query"]),
            tool("open_path", "Open a folder or file in Finder / its default app. Accepts ~ paths or names like downloads, desktop, documents.",
                 ["path": str("Path or folder name")], required: ["path"]),
            tool("set_timer", "Start a timer or reminder. When it fires, the pet announces the label with a sound.",
                 ["seconds": ["type": "integer", "minimum": 1, "description": "Delay in seconds"],
                  "label": str("What to remind the user about")], required: ["seconds", "label"]),
            tool("run_shortcut", "Run one of the user's Apple Shortcuts by its exact name.", ["name": str("Shortcut name")], required: ["name"]),
            tool("toggle_dark_mode", "Switch macOS between dark and light appearance."),
            tool("get_status", "Read Mac status: battery level, the frontmost app, or the song playing in Spotify.",
                 ["what": oneOf(["battery", "frontmost_app", "now_playing"], "What to read")], required: ["what"]),
            tool("perform_animation", "Make yourself (the pet) perform one of your animations, e.g. a jutsu, for fun.",
                 ["animation": oneOf(anims, "Animation id")], required: ["animation"]),
            tool("summon_ninja", "Bring another ninja pet onto the desktop.",
                 ["character_id": oneOf(Assets.pets.map(\.id), "Character id")], required: ["character_id"]),
            tool("dismiss_ninja", "Send a ninja pet away from the desktop.",
                 ["character_id": oneOf(Assets.pets.map(\.id), "Character id")], required: ["character_id"]),
        ]
    }

    /// Short status line shown in the speech bubble while a tool runs.
    static func statusLine(_ name: String, _ input: [String: Any]) -> String? {
        let s = { (k: String) in input[k] as? String ?? "" }
        switch name {
        case "open_app": return "Opening \(s("name"))…"
        case "quit_app": return "Closing \(s("name"))…"
        case "spotify_play": return "🎵 Finding \(s("query").isEmpty ? "that" : s("query"))…"
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
            return Mac.openURL(s("url"))
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
            return await Mac.toggleDarkMode()
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
        case "summon_ninja":
            guard let m = Assets.byId[s("character_id")] else { return .fail("Unknown character.") }
            App.delegate.summon(m.id)
            return .ok("\(m.displayName) has arrived.")
        case "dismiss_ninja":
            guard let m = Assets.byId[s("character_id")] else { return .fail("Unknown character.") }
            if m.id == pet.meta.id { return .fail("I can't dismiss myself while working on your mission.") }
            App.delegate.dismiss(m.id)
            return .ok("\(m.displayName) left.")
        default:
            return .fail("Unknown tool \(name).")
        }
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
