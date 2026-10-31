import AppKit
import ApplicationServices

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
            ?? apps.first { q.split(separator: " ").count <= 3 && q.contains(base($0)) && base($0).count >= 4 }
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

    static func openURL(_ raw: String, in appName: String) async -> ActionResult {
        guard !appName.isEmpty else { return openURL(raw) }
        guard let app = findApp(appName) else { return .fail("No app called \"\(appName)\" is installed.") }
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s) else { return .fail("That doesn't look like a link: \(raw)") }
        do {
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            return .ok("Opened \(s) in \(app.deletingPathExtension().lastPathComponent).")
        } catch { return .fail("Couldn't open it: \(error.localizedDescription)") }
    }

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

// MARK: - typing & keyboard shortcuts (needs Accessibility permission)

enum Keyboard {
    /// True when macOS lets us send keystrokes. Asks (opens System Settings) when `prompt` is set.
    static func allowed(prompt: Bool) -> Bool {
        if AXIsProcessTrusted() { return true }
        if prompt {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
        return false
    }

    static let permissionMessage = "I need Accessibility permission to type for you. I opened System Settings: " +
        "turn on Pet Agents under Privacy & Security → Accessibility, then ask again."

    private static let codes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34,
        "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46,
        ".": 47, "`": 50, "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51,
        "escape": 53, "esc": 53, "left": 123, "right": 124, "down": 125, "up": 126, "home": 115, "end": 119,
        "pageup": 116, "pagedown": 121, "f11": 103, "f12": 111,
    ]

    /// Press a combination like "cmd+shift+t", "return" or "escape".
    static func press(_ combo: String) -> Bool {
        var flags: CGEventFlags = []
        var key: CGKeyCode?
        for raw in combo.lowercased().replacingOccurrences(of: " ", with: "").split(separator: "+") {
            switch raw {
            case "cmd", "command", "⌘": flags.insert(.maskCommand)
            case "shift", "⇧": flags.insert(.maskShift)
            case "opt", "option", "alt", "⌥": flags.insert(.maskAlternate)
            case "ctrl", "control", "⌃": flags.insert(.maskControl)
            default: key = codes[String(raw)]
            }
        }
        guard let key else { return false }
        let src = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
        return true
    }

    /// Paste text into the focused field (works for any language), then put the clipboard back.
    static func paste(_ text: String) async {
        let pb = NSPasteboard.general
        let saved: [[(NSPasteboard.PasteboardType, Data)]] = (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
        }
        pb.clearContents()
        pb.setString(text, forType: .string)
        _ = press("cmd+v")
        await Mac.sleep(0.6)
        pb.clearContents()
        let items = saved.map { pairs -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (t, d) in pairs { item.setData(d, forType: t) }
            return item
        }
        if !items.isEmpty { pb.writeObjects(items) }
    }

    /// Bring an app to the front (launching it if needed) and wait until it is ready for typing.
    static func focus(app name: String) async -> ActionResult? {
        guard let url = Mac.findApp(name), let bundle = Bundle(url: url)?.bundleIdentifier else {
            return .fail("No app called \"\(name)\" is installed.")
        }
        let wasRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundle }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: cfg)
        for _ in 0..<40 where NSWorkspace.shared.frontmostApplication?.bundleIdentifier != bundle {
            await Mac.sleep(0.25)
            NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundle }?.activate()
        }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundle else {
            return .fail("\(name) didn't come to the front.")
        }
        await Mac.sleep(wasRunning ? 0.5 : 3.0)    // a freshly launched app needs time to draw its window
        return nil
    }
}

// MARK: - Steam games

enum Steam {
    struct Game { let id: String; let name: String }

    private static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Steam")
    }

    private static func field(_ key: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: "\"\(key)\"\\s+\"([^\"]*)\"") else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    /// Installed games from every Steam library (appmanifest_*.acf files).
    static func installed() -> [Game] {
        var libraries = [root]
        if let vdf = try? String(contentsOf: root.appendingPathComponent("steamapps/libraryfolders.vdf"), encoding: .utf8) {
            libraries += field("path", in: vdf).map { URL(fileURLWithPath: $0) }
        }
        var games: [String: Game] = [:]
        for lib in libraries {
            let dir = lib.appendingPathComponent("steamapps")
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            for f in files where f.hasPrefix("appmanifest_") && f.hasSuffix(".acf") {
                guard let text = try? String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8),
                      let id = field("appid", in: text).first, let name = field("name", in: text).first else { continue }
                if ["redistributable", "steamworks", "proton", "sdk", "runtime"].contains(where: name.lowercased().contains) { continue }
                games[id] = Game(id: id, name: name)
            }
        }
        return games.values.sorted { $0.name < $1.name }
    }

    private static func norm(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// "cs2" → "Counter-Strike 2", "arkham city" → "Batman: Arkham City GOTY".
    static func find(_ query: String) -> Game? {
        let q = norm(query.replacingOccurrences(of: "the game", with: ""))
        guard !q.isEmpty else { return nil }
        let games = installed()
        func initials(_ name: String) -> String {
            name.lowercased().split { !$0.isLetter && !$0.isNumber }
                .map { w in w.allSatisfy(\.isNumber) ? String(w) : String(w.prefix(1)) }.joined()
        }
        return games.first { norm($0.name) == q }
            ?? games.first { norm($0.name).hasPrefix(q) }
            ?? games.first { q.count >= 3 && norm($0.name).contains(q) }
            ?? games.first { initials($0.name) == q }
            ?? games.first { g in   // most query words appear in the name
                let words = query.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 }
                return !words.isEmpty && words.filter { norm(g.name).contains($0) }.count * 2 > words.count
            }
    }

    static func launch(_ query: String) -> ActionResult {
        if let g = find(query) {
            NSWorkspace.shared.open(URL(string: "steam://rungameid/\(g.id)")!)
            return .ok("Launching \(g.name) on Steam.")
        }
        let names = installed().map(\.name)
        let enc = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.valvesoftware.steam") != nil {
            NSWorkspace.shared.open(URL(string: "steam://openurl/https://store.steampowered.com/search/?term=\(enc)")!)
        }
        let list = names.isEmpty ? "No Steam games are installed." : "Installed: \(names.joined(separator: ", "))."
        return .fail("\(query) isn't installed, so I opened it in the Steam store. \(list)")
    }
}
