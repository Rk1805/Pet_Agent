import AppKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether Apple's on-device model can be used, and what to tell the user if not.
enum AIAvailability {
    static var available: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return SystemLanguageModel.default.availability == .available }
        #endif
        return false
    }

    static var hint: String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return ""
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence in System Settings and I'll understand much more."
            case .unavailable(.modelNotReady):
                return "Apple Intelligence is still downloading; I'll understand much more once it's ready."
            case .unavailable(.deviceNotEligible):
                return "This Mac can't run Apple Intelligence, so I only know simple commands."
            default:
                return "Apple Intelligence isn't available, so I only know simple commands."
            }
        }
        #endif
        return "Full AI needs macOS 26 with Apple Intelligence; until then I know simple commands."
    }
}

#if canImport(FoundationModels)

/// Runs missions on Apple's on-device language model. The model lives in macOS, not in this app.
@available(macOS 26.0, *)
@MainActor
final class OnDeviceAI {
    static let shared = OnDeviceAI()

    private var session: LanguageModelSession?
    private var sessionPet: String?
    private var lastUse = Date.distantPast
    private var lastToolFailed = false
    private var lastToolResult: String?

    private func instructions(_ pet: Pet) -> String {
        """
        You are \(pet.meta.name), a small pixel-art character who lives on the user's Mac desktop and helps them as a personal assistant. \(pet.meta.tagline)
        When the request needs an action on the Mac, call the matching tool. Pick sensible defaults instead of asking questions. \
        To write or ask something inside an app (Claude, Notes, ChatGPT…), use type_text. To start a game, use launch_game. \
        Don't call tools for chatting or jokes.
        Your reply appears in a tiny speech bubble: at most two short sentences (under 30 words), plain text, no lists. \
        Only mention what you actually did. If a tool says FAILED, say what went wrong. If you can't do something, say so.
        The user may write Hinglish (Hindi in English letters): chalao/bajao = play, kholo = open, band karo = close or stop, \
        agla = next, awaaz = volume, kam = lower, badhao = raise, yaad dilana = remind, baad = later. Reply in simple English.
        """
    }

    /// Reuses the session for follow-ups ("louder", "the other one") for a few minutes, then starts fresh.
    private func session(for pet: Pet) -> LanguageModelSession {
        if let s = session, sessionPet == pet.meta.id, Date().timeIntervalSince(lastUse) < 180 { return s }
        let tools: [any Tool] = Tools.schemas(for: pet).compactMap { PetTool(definition: $0, petID: pet.meta.id) }
        let s = LanguageModelSession(tools: tools, instructions: instructions(pet))
        session = s
        sessionPet = pet.meta.id
        return s
    }

    func prewarm(_ pet: Pet) {
        let s = session(for: pet)
        if !s.isResponding { s.prewarm() }
    }

    func run(_ text: String, pet: Pet) async -> (String, Bool) {
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
        let prompt = "\(text)\n\n(Local time: \(Date().formatted(date: .abbreviated, time: .shortened)). Frontmost app: \(front).)"
        for attempt in 0..<2 {
            let s = session(for: pet)
            lastUse = Date()
            lastToolFailed = false
            lastToolResult = nil
            do {
                let reply = try await s.respond(to: prompt).content
                return (Self.bubbleText(reply, fallback: lastToolResult), !lastToolFailed)
            } catch let e as LanguageModelSession.GenerationError {
                session = nil
                switch e {
                case .exceededContextWindowSize:
                    if attempt == 0 { continue }   // start a fresh conversation and try once more
                    return ("That's too much for me to keep in my head. Try a shorter request.", false)
                case .guardrailViolation:
                    return ("I can't help with that one.", false)
                case .unsupportedLanguageOrLocale:
                    return ("I don't understand that language yet. Try English.", false)
                case .assetsUnavailable:
                    return ("Apple Intelligence isn't ready right now. Try again in a bit.", false)
                default:
                    return ("I got confused. Could you say that another way?", false)
                }
            } catch {
                session = nil
                print("[ai error] \(error)")
                return ("I couldn't manage that one. Try saying it another way.", false)
            }
        }
        return ("I got confused. Could you say that another way?", false)
    }

    /// The small model tends to ramble or invent lists after acting. Keep the first one or two real sentences.
    static func bubbleText(_ raw: String, fallback: String?) -> String {
        let firstPara = raw.replacingOccurrences(of: "**", with: "")
            .components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        var sentences: [String] = []
        firstPara.enumerateSubstrings(in: firstPara.startIndex..., options: .bySentences) { s, _, _, stop in
            guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return }
            if s.hasSuffix(":") { stop = true; return }      // "Here are a few recommendations:" → drop
            sentences.append(s)
            if sentences.count == 2 { stop = true }
        }
        var text = sentences.joined(separator: " ")
        if text.count > 160 { text = String(text.prefix(157)) + "…" }
        if text.isEmpty { text = fallback ?? "Done!" }
        return text
    }

    /// Called by PetTool when the model decides to use a tool.
    func runTool(_ name: String, _ input: [String: Any], petID: String) async -> String {
        guard let pet = App.delegate.pet(petID) ?? App.delegate.anyPet() else { return "FAILED: no pet on screen." }
        if let line = Tools.statusLine(name, input) { pet.status(line) }
        let r = await Tools.run(name, input, pet: pet)
        if r.isError { lastToolFailed = true }
        lastToolResult = r.text
        print("[tool] \(name) \(input) -> \(r.isError ? "FAILED: " : "")\(r.text)")
        return r.isError ? "FAILED: \(r.text)" : r.text
    }
}

/// Writes text on request ("a haiku about rain") with Apple's on-device model.
enum Composer {
    @MainActor
    static func write(_ request: String) async -> String? {
        guard #available(macOS 26.0, *), AIAvailability.available else { return nil }
        let session = LanguageModelSession(instructions: """
            Write exactly what the user asks for. Output only the finished text: no title, no preface, \
            no quotes, no markdown. Keep it reasonably short unless asked otherwise.
            """)
        let text = try? await session.respond(to: "Write \(request)").content
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty ?? true) ? nil : text
    }
}

/// Wraps one entry of `Tools.schemas` as a Foundation Models tool, with its argument schema built at runtime.
@available(macOS 26.0, *)
struct PetTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema
    let petID: String

    init?(definition def: [String: Any], petID: String) {
        guard let name = def["name"] as? String, let schema = try? Self.schema(name, def["input_schema"] as? [String: Any] ?? [:])
        else { return nil }
        self.name = name
        self.description = def["description"] as? String ?? name
        self.parameters = schema
        self.petID = petID
    }

    func call(arguments: GeneratedContent) async throws -> String {
        let input = Self.plain(arguments) as? [String: Any] ?? [:]
        return await OnDeviceAI.shared.runTool(name, input, petID: petID)
    }

    /// JSON-schema-style properties (string / integer / boolean / string enum) → GenerationSchema.
    private static func schema(_ tool: String, _ input: [String: Any]) throws -> GenerationSchema {
        let props = input["properties"] as? [String: [String: Any]] ?? [:]
        let required = Set(input["required"] as? [String] ?? [])
        var out: [DynamicGenerationSchema.Property] = []
        for (key, spec) in props.sorted(by: { $0.key < $1.key }) {
            let desc = spec["description"] as? String
            let s: DynamicGenerationSchema
            if let choices = spec["enum"] as? [String] {
                s = DynamicGenerationSchema(name: "\(tool)_\(key)", description: desc, anyOf: choices)
            } else {
                switch spec["type"] as? String {
                case "integer": s = DynamicGenerationSchema(type: Int.self)
                case "boolean": s = DynamicGenerationSchema(type: Bool.self)
                default: s = DynamicGenerationSchema(type: String.self)
                }
            }
            out.append(.init(name: key, description: desc, schema: s, isOptional: !required.contains(key)))
        }
        return try GenerationSchema(root: DynamicGenerationSchema(name: "\(tool)_arguments", properties: out), dependencies: [])
    }

    /// GeneratedContent → plain Swift values ([String: Any], [Any], String, Double, Bool, NSNull).
    private static func plain(_ c: GeneratedContent) -> Any {
        switch c.kind {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let d): return d
        case .string(let s): return s
        case .array(let items): return items.map(plain)
        case .structure(let props, _): return props.mapValues(plain)
        @unknown default: return NSNull()
        }
    }
}

#endif
