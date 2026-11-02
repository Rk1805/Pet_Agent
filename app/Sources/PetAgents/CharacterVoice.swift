import AVFoundation
import CryptoKit
import Foundation

/// Characters speaking in their own (English) voice, cloned from a few seconds of their real speech by
/// F5-TTS (Apple MLX) in a small Python helper (tools/voice/voice_server.py, installed with
/// tools/voice/install_voice.sh).
/// The helper only runs while a character is talking and quits after a few idle minutes; fixed
/// lines ("Rasengan!") are pre-rendered at install time and play instantly from the cache.
@MainActor
final class CharacterVoice {
    static let shared = CharacterVoice()

    let root = Config.directory.appendingPathComponent("voice")
    private var specs: [String: (appliesTo: [String], lines: [String: [String]])] = [:]
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var waiting: [Int: URL] = [:]         // request id → where the result will be
    private var nextID = 1
    private var player: AVAudioPlayer?

    private init() { reload() }

    /// Read ~/Library/Application Support/PetAgents/voice/voices.json (copied there by the installer).
    func reload() {
        specs = [:]
        guard let data = try? Data(contentsOf: root.appendingPathComponent("voices.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        for (name, value) in json where !name.hasPrefix("_") {
            guard let v = value as? [String: Any] else { continue }
            specs[name] = (v["applies_to"] as? [String] ?? [name], v["lines"] as? [String: [String]] ?? [:])
        }
    }

    private func voiceName(_ pet: String) -> String? {
        specs.first { $0.key == pet || $0.value.appliesTo.contains(pet) }?.key
    }

    private var python: URL { root.appendingPathComponent("venv/bin/python") }

    /// Installed voices (for Settings).
    var installed: [String] {
        specs.keys.filter { FileManager.default.fileExists(atPath: root.appendingPathComponent("voices/\($0)/ref.wav").path) }.sorted()
    }

    func available(_ pet: String) -> Bool {
        guard App.config.characterVoices, let name = voiceName(pet) else { return false }
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: python.path)
            && fm.fileExists(atPath: root.appendingPathComponent("voice_server.py").path)
            && fm.fileExists(atPath: root.appendingPathComponent("voices/\(name)/ref.wav").path)
    }

    /// A fixed line for an event ("mission", "summon", a jutsu id), if the character has one.
    func line(_ event: String, for pet: String) -> String? {
        guard let name = voiceName(pet) else { return nil }
        return specs[name]?.lines[event]?.randomElement()
    }

    /// Text the TTS can say: no emoji, single spaces, at most 240 characters. Must match voice_server.py.
    static func clean(_ s: String) -> String {
        let kept = s.unicodeScalars.filter { !$0.properties.isEmojiPresentation && !($0.properties.isEmoji && $0.value > 0x238C) }
        let text = String(String.UnicodeScalarView(kept)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(text.prefix(240))
    }

    private func cacheURL(_ name: String, _ text: String) -> URL {
        let hash = Insecure.SHA1.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("cache/\(name)/\(hash).wav")
    }

    /// Say `text` in the pet's voice: instantly if cached, otherwise once the helper has rendered it.
    func speak(_ text: String, pet: String) {
        guard available(pet), let name = voiceName(pet) else { return }
        let t = Self.clean(text)
        guard t.contains(where: \.isLetter) else { return }
        let cached = cacheURL(name, t)
        if FileManager.default.fileExists(atPath: cached.path) { play(cached); return }
        guard startHelper() else { return }
        let id = nextID
        nextID += 1
        waiting[id] = cached
        let req: [String: Any] = ["id": id, "character": pet, "text": t]
        if let data = try? JSONSerialization.data(withJSONObject: req) {
            input?.write(data + Data("\n".utf8))
        }
    }

    /// Start the helper and load the voice while the pet works on a mission, so the reply is quick.
    func warm(_ pet: String) {
        guard available(pet), startHelper(),
              let data = try? JSONSerialization.data(withJSONObject: ["warm": true, "character": pet] as [String: Any]) else { return }
        input?.write(data + Data("\n".utf8))
    }

    // MARK: helper process

    private func startHelper() -> Bool {
        if process?.isRunning == true { return true }
        let p = Process()
        p.executableURL = python
        p.arguments = [root.appendingPathComponent("voice_server.py").path, "--root", root.path,
                       "--voices", root.appendingPathComponent("voices.json").path]
        let stdin = Pipe(), stdout = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = FileHandle(forWritingAtPath: "/dev/null")
        stdout.fileHandleForReading.readabilityHandler = { h in
            let chunk = h.availableData
            DispatchQueue.main.async { CharacterVoice.shared.received(chunk) }
        }
        p.terminationHandler = { _ in
            DispatchQueue.main.async {
                CharacterVoice.shared.process = nil
                CharacterVoice.shared.input = nil
                CharacterVoice.shared.waiting = [:]
            }
        }
        do { try p.run() } catch { print("[voice] helper didn't start: \(error)"); return false }
        process = p
        input = stdin.fileHandleForWriting
        return true
    }

    private func received(_ chunk: Data) {
        buffer.append(chunk)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let reply = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let id = reply["id"] as? Int, waiting.removeValue(forKey: id) != nil else { continue }
            if let path = reply["path"] as? String { play(URL(fileURLWithPath: path)) }
            else { print("[voice] \(reply["error"] ?? "failed")") }
        }
    }

    private func play(_ url: URL) {
        guard App.config.soundOn, let p = try? AVAudioPlayer(contentsOf: url) else { return }
        player?.stop()
        p.volume = Float(App.config.soundVolume)
        p.play()
        player = p
    }
}
