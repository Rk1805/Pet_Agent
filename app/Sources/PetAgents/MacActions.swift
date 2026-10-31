import AppKit

/// Result of an action: a short message for the model / speech bubble, and whether it failed.
struct ActionResult {
    let text: String
    let isError: Bool
    static func ok(_ t: String) -> ActionResult { .init(text: t, isError: false) }
    static func fail(_ t: String) -> ActionResult { .init(text: t, isError: true) }
}

enum Mac {
    // MARK: processes & AppleScript

    static func run(_ exe: String, _ args: [String]) async -> (code: Int32, out: String) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                do { try p.run() } catch {
                    cont.resume(returning: (-1, error.localizedDescription)); return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let out = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                cont.resume(returning: (p.terminationStatus, out))
            }
        }
    }

    static func osascript(_ source: String) async -> (ok: Bool, out: String) {
        let r = await run("/usr/bin/osascript", ["-e", source])
        return (r.code == 0, r.out)
    }

    static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: apps

    private static let aliases: [String: String] = [
        "chrome": "Google Chrome", "vscode": "Visual Studio Code", "vs code": "Visual Studio Code",
        "code": "Visual Studio Code", "settings": "System Settings", "system preferences": "System Settings",
        "preferences": "System Settings", "word": "Microsoft Word", "excel": "Microsoft Excel",
        "powerpoint": "Microsoft PowerPoint", "outlook": "Microsoft Outlook", "teams": "Microsoft Teams",
        "itunes": "Music", "apple music": "Music", "terminal app": "Terminal", "app store": "App Store",
    ]

    static func findApp(_ name: String) -> URL? {
        let fm = FileManager.default
        var q = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.hasSuffix(".app") { q.removeLast(4) }
        if q.hasPrefix("the ") { q.removeFirst(4) }
        if let a = aliases[q] { q = a.lowercased() }
        let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                    NSHomeDirectory() + "/Applications", "/System/Library/CoreServices", "/Applications/Setapp"]
        var apps: [URL] = []
        for d in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: d) else { continue }
            apps += items.filter { $0.hasSuffix(".app") }.map { URL(fileURLWithPath: d).appendingPathComponent($0) }
        }
        func base(_ u: URL) -> String { u.deletingPathExtension().lastPathComponent.lowercased() }
        return apps.first { base($0) == q }
            ?? apps.first { base($0).hasPrefix(q) }
            ?? apps.first { base($0).contains(q) }
            ?? apps.first { q.contains(base($0)) && base($0).count >= 4 }
    }

    static func openApp(_ name: String) async -> ActionResult {
        guard let url = findApp(name) else { return .fail("No app called \"\(name)\" is installed.") }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: cfg)
            return .ok("Opened \(url.deletingPathExtension().lastPathComponent).")
        } catch {
            return .fail("Couldn't open \(name): \(error.localizedDescription)")
        }
    }

    static func runningApp(_ name: String) -> NSRunningApplication? {
        let q = name.lowercased()
        let target = findApp(name).flatMap { Bundle(url: $0)?.bundleIdentifier }
        return NSWorkspace.shared.runningApplications.first {
            ($0.bundleIdentifier != nil && $0.bundleIdentifier == target) || ($0.localizedName?.lowercased() == q)
        }
    }

    static func quitApp(_ name: String) -> ActionResult {
        guard let app = runningApp(name) else { return .ok("\(name) isn't running.") }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return .fail("I won't quit myself!") }
        return app.terminate() ? .ok("Quit \(app.localizedName ?? name).") : .fail("\(name) refused to quit.")
    }

    // MARK: misc system

    static func openURL(_ raw: String) -> ActionResult {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") && !s.hasPrefix("spotify:") && !s.hasPrefix("mailto:") { s = "https://" + s }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(),
              ["http", "https", "spotify", "mailto"].contains(scheme) else { return .fail("That doesn't look like a link: \(raw)") }
        return NSWorkspace.shared.open(url) ? .ok("Opened \(s).") : .fail("Couldn't open \(s).")
    }

    static func searchWeb(_ query: String, site: String) -> ActionResult {
        var comps: URLComponents
        switch site {
        case "youtube":
            comps = URLComponents(string: "https://www.youtube.com/results")!
            comps.queryItems = [URLQueryItem(name: "search_query", value: query)]
        default:
            comps = URLComponents(string: "https://www.google.com/search")!
            comps.queryItems = [URLQueryItem(name: "q", value: query)]
        }
        guard let url = comps.url else { return .fail("Bad search.") }
        NSWorkspace.shared.open(url)
        return .ok("Searched \(site) for \(query).")
    }

    private static let folders: [String: String] = [
        "downloads": "~/Downloads", "desktop": "~/Desktop", "documents": "~/Documents", "home": "~",
        "pictures": "~/Pictures", "music": "~/Music", "movies": "~/Movies", "applications": "/Applications",
    ]

    static func openPath(_ raw: String) -> ActionResult {
        let key = raw.lowercased().trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "my ", with: "").replacingOccurrences(of: " folder", with: "")
        let path = NSString(string: folders[key] ?? raw).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else { return .fail("Nothing at \(path).") }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
        return .ok("Opened \(path).")
    }

    static func setVolume(level: Int?, muted: Bool?) async -> ActionResult {
        var parts: [String] = []
        let level = level.map { max(0, min(100, $0)) }
        if let level { parts.append("set volume output volume \(level)") }
        if let muted { parts.append(muted ? "set volume with output muted" : "set volume without output muted") }
        if parts.isEmpty { return .fail("Give a level or muted.") }
        let r = await osascript(parts.joined(separator: "\n"))
        if !r.ok { return .fail("Volume change failed: \(r.out)") }
        if let level { return .ok("Volume set to \(level)%.") }
        return .ok(muted == true ? "Muted." : "Unmuted.")
    }

    static func currentVolume() async -> Int {
        Int(await osascript("output volume of (get volume settings)").out) ?? 50
    }

    static func setAppearance(_ mode: String) async -> ActionResult {
        let value = mode == "dark" ? "true" : mode == "light" ? "false" : "not dark mode"
        let r = await osascript("""
        tell application "System Events" to tell appearance preferences
            set dark mode to \(value)
            return dark mode
        end tell
        """)
        if !r.ok { return .fail("Couldn't switch appearance (allow Pet Agents to control System Events in System Settings → Privacy & Security → Automation). \(r.out)") }
        return .ok(r.out == "true" ? "Dark mode on." : "Light mode on.")
    }

    static func runShortcut(_ name: String) async -> ActionResult {
        let r = await run("/usr/bin/shortcuts", ["run", name])
        return r.code == 0 ? .ok("Ran the \"\(name)\" shortcut. \(r.out)") : .fail("Shortcut \"\(name)\" failed: \(r.out)")
    }

    static func battery() async -> String {
        let r = await run("/usr/bin/pmset", ["-g", "batt"])
        // "-InternalBattery-0 (id=…)\t68%; discharging; 3:51 remaining present: true"
        let line = r.out.split(separator: "\n").first { $0.contains("%") }.map(String.init) ?? r.out
        let info = line.split(separator: "\t").last.map(String.init) ?? line
        return "Battery: " + info.replacingOccurrences(of: " present: true", with: "").replacingOccurrences(of: ";", with: ",")
    }
}

// MARK: - Spotify

enum Spotify {
    static let bundleID = "com.spotify.client"
    private static var token: (value: String, expires: Date)?

    static var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    /// open.spotify.com/track/ID?si=… or spotify:track:ID → spotify:track:ID
    static func normalize(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("spotify:") { return t }
        guard let url = URL(string: t), url.host?.contains("spotify.com") == true else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" && !$0.hasPrefix("intl-") && $0 != "embed" }
        guard parts.count >= 2, ["track", "album", "playlist", "artist", "episode", "show"].contains(parts[0]) else { return nil }
        return "spotify:\(parts[0]):\(parts[1])"
    }

    private static func accessToken() async throws -> String {
        if let t = token, t.expires > Date() { return t.value }
        let cfg = App.config
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        let basic = Data("\(cfg.spotifyClientId):\(cfg.spotifyClientSecret)".utf8).base64EncodedString()
        req.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("grant_type=client_credentials".utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = json["access_token"] as? String else {
            throw NSError(domain: "Spotify", code: 1, userInfo: [NSLocalizedDescriptionKey: "Spotify rejected the client ID / secret."])
        }
        let ttl = json["expires_in"] as? Double ?? 3600
        token = (value, Date().addingTimeInterval(ttl - 60))
        return value
    }

    /// Search the Spotify catalogue (needs Client ID + Secret in Settings). Returns (uri, description).
    static func search(_ query: String, kind: String) async throws -> (String, String)? {
        let tok = try await accessToken()
        var comps = URLComponents(string: "https://api.spotify.com/v1/search")!
        comps.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "type", value: kind),
                            URLQueryItem(name: "limit", value: "5")]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bucket = json[kind + "s"] as? [String: Any],
              let items = bucket["items"] as? [Any] else { return nil }
        for case let item as [String: Any] in items {     // playlist results can contain nulls
            guard let uri = item["uri"] as? String else { continue }
            let name = item["name"] as? String ?? query
            let artist = ((item["artists"] as? [[String: Any]])?.first?["name"] as? String).map { " by \($0)" } ?? ""
            return (uri, name + artist)
        }
        return nil
    }

    /// Launch Spotify if needed and wait until it answers AppleScript.
    static func ensureRunning() async -> Bool {
        if isRunning { return true }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: cfg)
        for _ in 0..<30 where !isRunning { await Mac.sleep(0.5) }
        await Mac.sleep(3)   // give the freshly launched player time to load
        return isRunning
    }

    static func play(uri: String, label: String) async -> ActionResult {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else {
            return .fail("Spotify isn't installed. You could open \(uri.replacingOccurrences(of: "spotify:", with: "https://open.spotify.com/").replacingOccurrences(of: ":", with: "/")) in the browser instead.")
        }
        guard await ensureRunning() else { return .fail("Spotify didn't start.") }
        for attempt in 0..<3 {
            let r = await Mac.osascript("tell application \"Spotify\" to play track \(Mac.quote(uri))")
            if !r.ok && r.out.contains("-1743") {
                return .fail("macOS blocked me from controlling Spotify. Allow it in System Settings → Privacy & Security → Automation.")
            }
            await Mac.sleep(1.2)
            let state = await Mac.osascript("tell application \"Spotify\" to player state as string")
            if state.out == "playing" { return .ok("Now playing \(label) on Spotify.") }
            if attempt < 2 { await Mac.sleep(1.5) }
        }
        return .fail("Spotify didn't start playing \(label). Is it signed in?")
    }

    static func control(_ action: String) async -> ActionResult {
        let scripts: [String: String] = [
            "play": "play", "pause": "pause", "toggle": "playpause", "next": "next track",
            "previous": "previous track", "shuffle_on": "set shuffling to true", "shuffle_off": "set shuffling to false",
        ]
        if action == "now_playing" {
            guard isRunning else { return .ok("Spotify isn't running, so nothing is playing.") }
            let r = await Mac.osascript("""
            tell application "Spotify"
                if player state is stopped then return "nothing"
                return (name of current track) & " by " & (artist of current track) & " (" & (player state as string) & ")"
            end tell
            """)
            return r.ok ? .ok(r.out) : .fail(r.out)
        }
        guard let cmd = scripts[action] else { return .fail("Unknown Spotify action \(action).") }
        if !isRunning {
            if action == "pause" { return .ok("Spotify isn't running.") }
            guard await ensureRunning() else { return .fail("Spotify isn't installed or didn't start.") }
        }
        let r = await Mac.osascript("tell application \"Spotify\" to \(cmd)")
        return r.ok ? .ok("Spotify: \(action.replacingOccurrences(of: "_", with: " ")).") : .fail("Spotify said: \(r.out)")
    }
}
