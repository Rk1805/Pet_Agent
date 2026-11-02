import AppKit
import AVFoundation

/// Character voice lines, jutsu sound effects and themes from Sounds/ (see Sounds/sounds.json).
/// Clips are fetched locally by tools/sounds/fetch_sounds.py; if they're missing the app stays quiet.
@MainActor
final class Sound {
    static let shared = Sound()

    private struct Map: Decodable {
        let characters: [String: [String: [String]]]
        let shared: [String: [String]]
        let themes: [String: String]
    }

    private let folder: URL?
    private let map: Map?
    private var voices: [String: AVAudioPlayer] = [:]     // one voice per pet at a time
    private var theme: AVAudioPlayer?
    private var durations: [String: Double] = [:]

    private init() {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let r = Bundle.main.resourceURL { candidates.append(r.appendingPathComponent("Sounds")) }
        candidates.append(Assets.root.deletingLastPathComponent().appendingPathComponent("Sounds"))   // repo: preview/../Sounds
        folder = candidates.first { fm.fileExists(atPath: $0.appendingPathComponent("sounds.json").path) }
        map = folder.flatMap { try? JSONDecoder().decode(Map.self, from: Data(contentsOf: $0.appendingPathComponent("sounds.json"))) }
    }

    var available: Bool { map != nil }

    /// (clips listed, clips present on disk) — for `PetAgents --sound-check`.
    var coverage: (listed: Int, present: Int, folder: String) {
        guard let map else { return (0, 0, "none") }
        let names = Set(map.characters.values.flatMap { $0.values.flatMap { $0 } } + map.shared.values.flatMap { $0 } + Array(map.themes.values))
        return (names.count, names.filter { url($0) != nil }.count, folder?.path ?? "none")
    }
    var themeNames: [String] { map.map { Array($0.themes.keys).sorted() } ?? [] }

    private var enabled: Bool { App.config.soundOn }
    private var volume: Float { Float(App.config.soundVolume) }

    /// Clips for an event, falling back from "naruto_shippuden" to "naruto".
    private func clips(_ pet: String, _ event: String) -> [String] {
        guard let map else { return [] }
        if let c = map.characters[pet]?[event], !c.isEmpty { return c }
        let base = pet.replacingOccurrences(of: "_shippuden", with: "")
        if base != pet, let c = map.characters[base]?[event], !c.isEmpty { return c }
        return []
    }

    private func url(_ name: String) -> URL? {
        guard let u = folder?.appendingPathComponent(name), FileManager.default.fileExists(atPath: u.path) else { return nil }
        return u
    }

    /// Play a character's line / jutsu sound. Prefers short clips; long ones fade out after ~6 s.
    @discardableResult
    func play(_ event: String, for pet: String) -> Bool {
        guard enabled else { return false }
        // Characters with an installed voice say their own (English) line; clips then only add sound effects.
        let voice = CharacterVoice.shared
        if voice.available(pet), let line = voice.line(event, for: pet) {
            voice.speak(line, pet: pet)
            if event == "mission" || event == "summon" { return true }
        }
        let options = clips(pet, event).compactMap { name in url(name).map { (name, $0) } }
        guard !options.isEmpty else { return false }
        let short = options.filter { duration($0.1) <= 6 }
        guard let (_, u) = (short.isEmpty ? options : short).randomElement(),
              let p = try? AVAudioPlayer(contentsOf: u) else { return false }
        voices[pet]?.stop()
        p.volume = volume
        p.play()
        voices[pet] = p
        if p.duration > 6.5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) { [weak p] in p?.setVolume(0, fadeDuration: 0.8) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.4) { [weak p] in p?.stop() }
        }
        return true
    }

    func playShared(_ name: String) {
        guard enabled, let file = map?.shared[name]?.randomElement(), let u = url(file),
              let p = try? AVAudioPlayer(contentsOf: u) else { return }
        p.volume = volume * 0.8
        p.play()
        voices["_" + name] = p
    }

    private func duration(_ u: URL) -> Double {
        if let d = durations[u.lastPathComponent] { return d }
        let d = (try? AVAudioPlayer(contentsOf: u))?.duration ?? 0
        durations[u.lastPathComponent] = d
        return d
    }

    // MARK: themes

    /// "naruto", "sad", "blue bird", "pain", "spider-man"… → plays the closest theme. Returns its name.
    func playTheme(_ query: String) -> String? {
        guard let map else { return nil }
        let q = query.lowercased()
        let aliases = ["sad": "sadness and sorrow", "sadness": "sadness and sorrow", "battle": "fighting spirit",
                       "fight": "fighting spirit", "spiderman": "spider-man", "spider man": "spider-man", "main": "naruto"]
        let key = map.themes.keys.first { $0 == q } ?? aliases.first { q.contains($0.key) }?.value
            ?? map.themes.keys.first { q.contains($0) || $0.contains(q) }
        guard let key, let file = map.themes[key], let u = url(file), let p = try? AVAudioPlayer(contentsOf: u) else { return nil }
        theme?.stop()
        p.volume = volume
        p.play()
        theme = p
        return key
    }

    func stopTheme() -> Bool {
        guard let t = theme, t.isPlaying else { return false }
        t.setVolume(0, fadeDuration: 0.6)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { t.stop() }
        theme = nil
        return true
    }
}
