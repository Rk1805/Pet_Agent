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
    private var waiting: [Int: (token: Int, index: Int)] = [:]   // helper request id → which sentence of which reply
    private var nextID = 1
    private var player: AVAudioPlayer?
    private let finished = PlaybackDelegate()

    /// The reply being spoken: its sentences' audio (nil = still rendering) and how far playback got.
    private struct Utterance {
        let token: Int
        var audio: [URL?]
        var next = 0
        var started = false
        var playing = false
        var onStart: (() -> Void)?
    }
    private var current: Utterance?
    private var token = 0

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

    /// Sentences as the helper renders them (it splits on the same punctuation).
    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        var cur = ""
        for ch in text {
            cur.append(ch)
            if ".!?".contains(ch) {
                let t = cur.trimmingCharacters(in: .whitespaces)
                if t.contains(where: \.isLetter) { out.append(t) }
                cur = ""
            }
        }
        let tail = cur.trimmingCharacters(in: .whitespaces)
        if tail.contains(where: \.isLetter) { out.append(tail) }
        return out
    }

    /// Say `text` in the pet's voice. `onStart` runs at the moment the voice begins, so the caller can show
    /// the text at the same instant; if the voice isn't ready within 7 s it runs anyway and the voice is
    /// dropped (text never waits on audio forever, and audio never trails the text).
    func speak(_ text: String, pet: String, onStart: (() -> Void)? = nil) {
        guard available(pet), let name = voiceName(pet) else { onStart?(); return }
        let whole = Self.clean(text)
        // Fixed lines are pre-rendered whole ("What a drag. Fine, I'll do it."): use that if it exists.
        let parts = FileManager.default.fileExists(atPath: cacheURL(name, whole).path) ? [whole] : Self.sentences(whole)
        guard !parts.isEmpty else { onStart?(); return }
        token += 1
        let tok = token
        player?.stop()
        var u = Utterance(token: tok, audio: parts.map { _ in nil }, onStart: onStart)
        var needHelper = false
        for (i, sentence) in parts.enumerated() {
            let cached = cacheURL(name, sentence)
            if FileManager.default.fileExists(atPath: cached.path) { u.audio[i] = cached } else { needHelper = true }
        }
        current = u
        if needHelper {
            guard startHelper() else { current = nil; onStart?(); return }
            for (i, sentence) in parts.enumerated() where u.audio[i] == nil {
                let id = nextID
                nextID += 1
                waiting[id] = (tok, i)
                if let data = try? JSONSerialization.data(withJSONObject: ["id": id, "character": pet, "text": sentence] as [String: Any]) {
                    input?.write(data + Data("\n".utf8))
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
                guard let self, var u = self.current, u.token == tok, !u.started else { return }
                u.onStart?(); u.onStart = nil
                self.current = nil                         // too slow this time: text only
            }
        }
        advance()
    }

    /// Play the next sentence if it's ready; the first one also triggers `onStart`.
    private func advance() {
        guard var u = current, !u.playing else { return }
        guard u.next < u.audio.count else { current = nil; return }
        guard let url = u.audio[u.next] else { return }   // still rendering
        if !u.started { u.started = true; u.onStart?(); u.onStart = nil }
        u.next += 1
        u.playing = true
        current = u
        guard App.config.soundOn, let p = try? AVAudioPlayer(contentsOf: url) else { sentenceEnded(); return }
        p.volume = Float(App.config.soundVolume)
        p.delegate = finished
        finished.onEnd = { [weak self] in self?.sentenceEnded() }
        p.play()
        player = p
    }

    private func sentenceEnded() {
        guard var u = current else { return }
        u.playing = false
        current = u
        advance()
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
                  let id = reply["id"] as? Int, let slot = waiting.removeValue(forKey: id) else { continue }
            guard let path = reply["path"] as? String else { print("[voice] \(reply["error"] ?? "failed")"); continue }
            guard var u = current, u.token == slot.token, slot.index < u.audio.count else { continue }   // stale reply
            u.audio[slot.index] = URL(fileURLWithPath: path)
            current = u
            advance()
        }
    }
}

/// Tells CharacterVoice when a sentence finishes so the next one starts right after it.
final class PlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    var onEnd: (() -> Void)?
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.onEnd?() }
    }
}
