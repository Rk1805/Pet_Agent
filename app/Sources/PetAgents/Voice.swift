import AppKit
import AVFoundation
import Speech

/// Voice input with Apple's built-in, on-device speech recognition (English).
/// macOS 26+: SpeechAnalyzer + SpeechTranscriber (live, punctuated). Older macOS: SFSpeechRecognizer on-device.
/// The microphone and the recogniser only run while you talk.
@MainActor
final class Voice {
    static let shared = Voice()

    private(set) var listening = false
    private var engine: AVAudioEngine?
    private var session: AnyObject?                 // SpeechAnalyzerSession (macOS 26) or LegacySession
    private var silenceTimer: Timer?
    private var heardAt: Date?
    private var startedAt = Date()
    private var text = ""
    private var onUpdate: ((String) -> Void)?
    private var onDone: ((String?) -> Void)?

    /// Start listening. `update` gets the live transcript; `done` gets the final text (nil if nothing / failed).
    func start(update: @escaping (String) -> Void, done: @escaping (String?) -> Void) {
        guard !listening else { return }
        listening = true
        text = ""
        heardAt = nil
        startedAt = Date()
        onUpdate = update
        onDone = done
        Task { @MainActor in
            if let problem = await self.prepare() {
                self.listening = false
                update(problem)
                done(nil)
                return
            }
            NSSound(named: "Tink")?.play()
            update("🎤 Listening…")
            self.silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkSilence() }
            }
        }
    }

    /// Stop listening and hand the transcript to `done`.
    func stop() {
        guard listening else { return }
        listening = false
        silenceTimer?.invalidate()
        silenceTimer = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        NSSound(named: "Pop")?.play()
        let current = session
        session = nil
        Task { @MainActor in
            if #available(macOS 26.0, *), let s = current as? SpeechAnalyzerSession { await s.finish() }
            if let s = current as? LegacySession { await s.finish() }
            let final = Voice.tidy(self.text)
            self.onDone?(final.isEmpty ? nil : final)
            self.onDone = nil
            self.onUpdate = nil
        }
    }

    /// Stop by itself: 1.4 s of quiet after you've said something, or 7 s of nothing at all.
    private func checkSilence() {
        guard listening else { return }
        if let heard = heardAt { if Date().timeIntervalSince(heard) > 1.4 { stop() } }
        else if Date().timeIntervalSince(startedAt) > 7 { stop() }
    }

    fileprivate func received(_ transcript: String) {
        guard transcript != text else { return }
        text = transcript
        if !transcript.trimmingCharacters(in: .whitespaces).isEmpty { heardAt = Date() }
        onUpdate?("🎤 " + transcript)
    }

    // MARK: setup

    private func prepare() async -> String? {
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        guard mic else {
            return "I can't hear you: allow the microphone for Pet Agents in System Settings → Privacy & Security → Microphone."
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return "I can't find a microphone." }

        let feed: (AVAudioPCMBuffer) -> Void
        if #available(macOS 26.0, *), SpeechTranscriber.isAvailable {
            let s = SpeechAnalyzerSession()
            if let problem = await s.begin(inputFormat: format, onText: { [weak self] t in
                Task { @MainActor in self?.received(t) }
            }) { return problem }
            session = s
            feed = s.feed
        } else {
            let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { c in
                SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
            }
            guard status == .authorized else {
                return "Allow Speech Recognition for Pet Agents in System Settings → Privacy & Security."
            }
            let s = LegacySession()
            if let problem = s.begin(onText: { [weak self] t in Task { @MainActor in self?.received(t) } }) { return problem }
            session = s
            feed = s.feed
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in feed(buffer) }
        do { try engine.start() } catch { return "The microphone didn't start: \(error.localizedDescription)" }
        self.engine = engine
        return nil
    }

    /// Spoken-text clean-up before it becomes a mission: "3 p.m." → "3 pm", no final full stop.
    nonisolated static func tidy(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"\b([ap])\.m\."#, with: "$1m", options: [.regularExpression, .caseInsensitive])
        // "Claude" is sometimes heard as "code"/"cloud" in chat phrasings, where VS Code makes no sense.
        for p in [#"\b(chat (?:in|on|with)) (?:code|cloud|clod)\b"#, #"\b(ask|tell|message) (?:code|cloud|clod)\b"#,
                  #"\b(send (?:it|this|that) to) (?:code|cloud|clod)\b"#] {
            t = t.replacingOccurrences(of: p, with: "$1 Claude", options: [.regularExpression, .caseInsensitive])
        }
        return t.trimmingCharacters(in: CharacterSet(charactersIn: " \n.。"))
    }

    /// Words the recogniser should expect: your apps, games and pet characters.
    nonisolated static func vocabulary() -> [String] {
        var words = ["WhatsApp", "Spotify", "Steam", "Claude", "ChatGPT", "Rasengan", "jutsu",
                     "ask Claude", "in Claude", "new chat in Claude", "tell Claude", "send it to Claude",
                     "ask ChatGPT", "on WhatsApp", "on Spotify", "on Steam", "send it", "remind me to",
                     "what's on my calendar", "summon", "dismiss", "web swing"]
        let fm = FileManager.default
        for dir in ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"] {
            words += ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".app") }
                .map { String($0.dropLast(4)) }
        }
        words += Assets.pets.map(\.name)
        words += Steam.installed().map(\.name)
        return Array(Set(words)).sorted().prefix(300).map { $0 }
    }
}

// MARK: - macOS 26: SpeechAnalyzer

@available(macOS 26.0, *)
final class SpeechAnalyzerSession {
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var results: Task<Void, Never>?

    /// The best English locale for this Mac (en-IN in India, en-GB in the UK, …).
    static func locale() async -> Locale {
        let current = Locale.current
        let english = current.language.languageCode?.identifier == "en" ? current
            : Locale(identifier: "en-" + (current.region?.identifier ?? "US"))
        if let l = await SpeechTranscriber.supportedLocale(equivalentTo: english) { return l }
        if let l = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) { return l }
        return Locale(identifier: "en-US")
    }

    func begin(inputFormat: AVAudioFormat, onText: @escaping @Sendable (String) -> Void) async -> String? {
        let transcriber = SpeechTranscriber(locale: await Self.locale(), transcriptionOptions: [],
                                            reportingOptions: [.volatileResults], attributeOptions: [])
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()     // one-time download of the English speech model
            }
        } catch { return "I couldn't download Apple's speech model: \(error.localizedDescription)" }

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]),
              let converter = AVAudioConverter(from: inputFormat, to: format) else {
            return "Speech recognition isn't available for this microphone."
        }
        let context = AnalysisContext()
        context.contextualStrings[.general] = Voice.vocabulary()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        do {
            try await analyzer.setContext(context)
            try await analyzer.prepareToAnalyze(in: format)
            try await analyzer.start(inputSequence: stream)
        } catch { return "Speech recognition didn't start: \(error.localizedDescription)" }

        results = Task {
            var final = ""
            do {
                for try await r in transcriber.results {
                    let piece = String(r.text.characters)
                    if r.isFinal { final += piece; onText(final) } else { onText(final + piece) }
                }
            } catch {}
        }
        self.analyzer = analyzer
        self.input = continuation
        self.converter = converter
        self.targetFormat = format
        return nil
    }

    /// Called on the audio thread for every microphone buffer.
    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let targetFormat, let input else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        var used = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if used { status.pointee = .noDataNow; return nil }
            used = true
            status.pointee = .haveData
            return buffer
        }
        if error == nil, out.frameLength > 0 { input.yield(AnalyzerInput(buffer: out)) }
    }

    func finish() async {
        input?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await results?.value
    }

    /// Transcribe an audio file (used by `PetAgents --transcribe <file>` to test recognition).
    static func transcribe(file url: URL) async -> String {
        guard let file = try? AVAudioFile(forReading: url) else { return "(can't read \(url.path))" }
        final class Box: @unchecked Sendable { var text = "" }
        let got = Box()
        let s = SpeechAnalyzerSession()
        if let problem = await s.begin(inputFormat: file.processingFormat, onText: { got.text = $0 }) { return problem }
        while true {
            guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096) else { break }
            do { try file.read(into: buf) } catch { break }
            if buf.frameLength == 0 { break }
            s.feed(buf)
        }
        await s.finish()
        return Voice.tidy(got.text)
    }
}

// MARK: - older macOS: SFSpeechRecognizer, on-device

final class LegacySession {
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func begin(onText: @escaping (String) -> Void) -> String? {
        let current = Locale.current
        let english = current.language.languageCode?.identifier == "en" ? current : Locale(identifier: "en-US")
        guard let recognizer = SFSpeechRecognizer(locale: english) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else { return "Speech recognition isn't available right now." }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        req.contextualStrings = Voice.vocabulary()
        req.addsPunctuation = true
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            if let result { onText(result.bestTranscription.formattedString) }
        }
        request = req
        return nil
    }

    func feed(_ buffer: AVAudioPCMBuffer) { request?.append(buffer) }

    func finish() async {
        request?.endAudio()
        try? await Task.sleep(nanoseconds: 1_200_000_000)    // let the last words come through
        task?.finish()
        task = nil
    }
}
