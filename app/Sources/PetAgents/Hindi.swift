import Foundation
#if canImport(Translation)
import Translation
#endif

/// Hindi support. Apple's on-device language model doesn't speak Hindi, so:
/// 1. Common Hindi / Hinglish commands are rewritten into the English phrasing LocalCommands understands.
/// 2. Other Devanagari text is translated on-device (Apple Translation) when the Hindi pack is installed.
enum Hindi {
    static func hasDevanagari(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x0900...0x097F).contains($0.value) }
    }

    /// ०१२… → 012…
    static func asciiDigits(_ s: String) -> String {
        String(s.unicodeScalars.map { u -> Character in
            (0x0966...0x096F).contains(u.value) ? Character(UnicodeScalar(u.value - 0x0966 + 48)!) : Character(u)
        })
    }

    // MARK: vocabulary (Latin "Hinglish" spellings and Devanagari)

    private static let play = #"(?:chala\s*(?:o|do|de|dena|iye|na)|bajaa?\s*(?:o|do|de|dena|iye|na)|laga\s*(?:o|do|de|dena|iye|na)|suna\s*(?:o|do|de|dena|iye|na)|play\s*kar\s*(?:o|do|de|dena|na)?|चलाओ|चला\s*दो|चला\s*दीजिए|बजाओ|बजा\s*दो|लगाओ|लगा\s*दो|सुनाओ|सुना\s*दो|प्ले\s*करो)"#
    private static let open = #"(?:khol\s*(?:o|do|de|dena|iye|na)|open\s*kar\s*(?:o|do|de|dena|na)?|खोलो|खोल\s*दो|खोल\s*दीजिए|ओपन\s*करो)"#
    private static let close = #"(?:band\s*kar\s*(?:o|do|de|dena|na)?|bnd\s*kar\s*(?:o|do)?|quit\s*kar\s*(?:o|do)?|बंद\s*करो|बंद\s*कर\s*दो|बन्द\s*करो)"#
    private static let song = #"(?:gaa?na|gaa?ne|song|songs|music|गाना|गाने|म्यूजिक|संगीत)"#
    private static let volume = #"(?:aa?waa?z|avaa?z|volume|sound|आवाज़|आवाज|वॉल्यूम)"#
    private static let down = #"(?:kam|dheere|dhire|ghata\s*(?:o|do)|कम|धीरे|घटाओ)"#
    private static let up = #"(?:badha\s*(?:o|do)|tez|zyada|jyada|बढ़ाओ|बढाओ|तेज़|तेज|ज़्यादा|ज्यादा)"#
    private static let remind = #"(?:yaad\s*dila\s*(?:na|o|do|dena|iyo|iye|देना)?|remind\s*kar\s*(?:na|o|do|dena)?|याद\s*दिला(?:ना|ओ|\s*दो|\s*देना)?)"#
    private static let unit = #"(minutes?|mins?|minat|mint|minute|मिनट|ghante|ghanta|ghanton|hours?|घंटे|घंटा|seconds?|secs?|सेकंड)"#
    private static let after = #"(?:baad|bad|mein|me|mai|में|बाद)"#
    private static let filler = #"please|plz|pls|zara|jara|yaar|yar|bhai|bro|ji|kripya|ज़रा|जरा|प्लीज़|प्लीज|भाई|यार|कृपया"#

    /// Whole words only. `\b` doesn't work for Devanagari (vowel signs count as non-word), so use letter/mark lookarounds.
    private static func word(_ p: String) -> String { #"(?<![\p{L}\p{M}])(?:"# + p + #")(?![\p{L}\p{M}])"# }

    private static func m(_ text: String, _ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let r = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<r.numberOfRanges).map { i in Range(r.range(at: i), in: text).map { String(text[$0]) } ?? "" }
    }

    private static func strip(_ text: String, _ patterns: [String]) -> String {
        var t = text
        for p in patterns { t = t.replacingOccurrences(of: p, with: " ", options: [.regularExpression, .caseInsensitive]) }
        return t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    private static func englishUnit(_ u: String) -> String {
        let u = u.lowercased()
        if u.hasPrefix("gh") || u.hasPrefix("hour") || u.hasPrefix("घं") { return "hours" }
        if u.hasPrefix("sec") || u.hasPrefix("से") { return "seconds" }
        return "minutes"
    }

    /// Rewrites a Hindi / Hinglish command into English, e.g. "arijit singh ka gaana chalao" → "play arijit singh".
    /// Returns nil when nothing matches (the text may already be English).
    static func toEnglishCommand(_ raw: String) -> String? {
        var t = asciiDigits(raw).lowercased()
        t = t.replacingOccurrences(of: #"[।?!.,]+"#, with: " ", options: .regularExpression)
        t = strip(t, [#"^(?:ek\s*kaam\s*karo|एक\s*काम\s*करो)"#, word(filler), #"\b(?:na|naa)$"#])
        if t.isEmpty { return nil }

        // Volume: "awaaz kam karo", "volume badhao", "awaaz 30 kar do", "awaaz band karo"
        if m(t, volume) != nil {
            if let g = m(t, #"(\d{1,3})"#) { return "volume \(g[1])" }
            if m(t, close) != nil || m(t, #"\bmute\b|म्यूट"#) != nil { return "mute" }
            if m(t, down) != nil { return "volume down" }
            if m(t, up) != nil { return "volume up" }
        }
        // Reminders and timers: "10 minute baad yaad dilana paani peena", "paani peene ke liye 10 min baad yaad dilana"
        if m(t, remind) != nil || m(t, #"timer|टाइमर"#) != nil, let g = m(t, #"(\d+)\s*"# + unit + #"(?:\s*"# + after + #")?"#) {
            let amount = "\(g[1]) \(englishUnit(g[2]))"
            if m(t, remind) == nil { return "timer for \(amount)" }
            let label = strip(t, [NSRegularExpression.escapedPattern(for: g[0]), remind, word(#"mujhe|muje|ki|ke\s*liye|ka|timer|laga\s*(?:o|do)|मुझे|कि|के\s*लिए"#)])
            return label.isEmpty ? "timer for \(amount)" : "remind me in \(amount) to \(label)"
        }
        // Typing into apps: "claude mein hello likho", "claude se pucho chawal kaise banaye"
        if let g = m(t, #"^(claude|chatgpt|perplexity|gemini)\s*(?:se|से|ko|को)\s*(?:pucho|poocho|puchho|puchiye|पूछो|बोलो|bolo)\s+(.+)$"#)
            ?? m(t, #"^(.+?)\s+(claude|chatgpt|perplexity)\s*(?:se|से)\s*(?:pucho|poocho|puchho|पूछो)$"#).map({ [$0[0], $0[2], $0[1]] }) {
            return "ask \(g[1]) \(g[2])"
        }
        if let g = m(t, #"^([\w .+-]{2,30}?)\s+(?:mein|me|mai|में|par|pe|पर|पे)\s+(.+?)\s+(?:likho|likh\s*do|likhiye|type\s*kar\s*(?:o|do)?|लिखो|लिख\s*दो|टाइप\s*करो)(\s*(?:aur|और)\s*(?:send|bhejo|भेजो)\s*(?:kar\s*do|karo)?)?$"#) {
            return "type \(g[2]) in \(g[1])" + (g[3].isEmpty ? "" : " and send")
        }
        // Games: "steam pe batman khelo", "arkham city game chalao"
        if m(t, #"khelo|khel\s*do|खेलो|steam|स्टीम|\bgame\b|गेम"#) != nil, m(t, play + "|khelo|khel\\s*do|खेलो|" + open) != nil {
            let what = strip(t, [#"(?:steam|स्टीम)\s*(?:pe|par|pr|mein|me|पे|पर|में)?"#, word(#"game|गेम|wala|वाला|ka|का"#),
                                 #"khelo|khel\s*do|खेलो"#, play, open])
            if !what.isEmpty { return "play \(what) on steam" }
        }
        // Characters: "venom ko bulao", "doc ock ko bhejo"
        if let g = m(t, #"^(.+?)\s+(?:ko|को)\s+(?:bulao|bula\s*do|बुलाओ|बुला\s*दो)$"#) { return "summon \(g[1])" }
        if let g = m(t, #"^(.+?)\s+(?:ko|को)\s+(?:bhejo|bhej\s*do|hatao|भेजो|हटाओ)$"#) { return "dismiss \(g[1])" }
        // Music controls
        if m(t, #"^(?:agla|agli|next|अगला)\b"#) != nil || m(t, #"skip\s*kar"#) != nil { return "next" }
        if m(t, #"^(?:pichla|pichhla|previous|पिछला)\b"#) != nil { return "previous" }
        if m(t, #"(?:kaun\s*sa|konsa|kya)\s*"# + song + #"|कौन\s*सा\s*गाना"#) != nil { return "what's playing" }
        if m(t, close) != nil || m(t, #"\b(?:ruko|rok\s*do|pause\s*kar)|रोको|रोक\s*दो"#) != nil {
            let target = strip(t, [close, #"\b(?:ruko|rok\s*do|pause\s*kar\s*(?:o|do)?)\b|रोको|रोक\s*दो"#])
            if target.isEmpty || m(target, "^" + song + "$") != nil || m(target, #"^(?:spotify|स्पॉटिफाई)$"#) != nil { return "pause" }
            return "quit \(target)"
        }
        if m(t, play) != nil {
            var what = strip(t, [play, #"(?:spotify|स्पॉटिफाई)\s*(?:pe|par|pr|mein|me|पे|पर|में)?"#,
                                 word(#"ka|ki|ke|wala|vala|wale|का|की|के|वाला|वाले"#), word(song),
                                 word(#"koi|kuch|ek|achha|accha|कोई|कुछ|एक"#)])
            if m(t, #"youtube|यूट्यूब"#) != nil {
                what = strip(what, [#"youtube\s*(?:pe|par|pr|mein|me)?|यूट्यूब\s*(?:पे|पर|में)?"#])
                return what.isEmpty ? "open youtube" : "youtube \(what)"
            }
            if what.isEmpty || m(what, #"^(?:wapas|phir\s*se|chalu)$"#) != nil { return "play music" }
            return "play \(what)"
        }
        if m(t, #"(?:wapas|phir\s*se)\s*"# + play + #"|chalu\s*kar"#) != nil { return "resume" }
        // Open apps / sites: "notes kholo", "youtube khol do"
        if m(t, open) != nil {
            let what = strip(t, [open, #"\b(?:app|application|website|site)\b|ऐप"#])
            return what.isEmpty ? nil : "open \(what)"
        }
        // Search
        if let g = m(t, #"^(?:youtube|यूट्यूब)\s*(?:pe|par|pr|mein|me|पे|पर|में)\s*(.+?)\s*(?:dikhao|dikha\s*do|chalao|search\s*karo|दिखाओ)?$"#) {
            return "youtube \(g[1])"
        }
        if let g = m(t, #"^(.+?)\s*(?:search\s*kar\s*(?:o|do)?|google\s*kar\s*(?:o|do)?|dhoo?n?d(?:h)?\s*(?:o|do)|khojo|खोजो|ढूंढो|ढूँढो|सर्च\s*करो)$"#) {
            return "search \(g[1])"
        }
        // Status
        if m(t, #"battery|बैटरी"#) != nil { return "battery" }
        if m(t, #"kitne\s*baje|time\s*kya|samay\s*kya|कितने\s*बजे|समय\s*क्या|टाइम\s*क्या"#) != nil { return "what time is it" }
        if m(t, #"aaj\s*(?:kaun\s*sa|konsa|kaunsa|kya)\s*(?:din|date|tareekh|tarikh)|aaj\s*ki\s*(?:date|tareekh|tarikh)|आज\s*कौन\s*सा\s*दिन|आज\s*की\s*तारीख|आज\s*क्या\s*तारीख"#) != nil {
            return "what's the date"
        }
        if m(t, #"dark\s*mode|डार्क\s*मोड"#) != nil { return "dark mode" }
        if m(t, #"light\s*mode|लाइट\s*मोड"#) != nil { return "light mode" }
        if m(t, #"jutsu|जुत्सु"#) != nil { return "jutsu" }
        return nil
    }

    // MARK: on-device translation (macOS 26+, Hindi pack from System Settings or the Home window)

    enum PackStatus { case checking, installed, downloadable, unsupported }

    static func packStatus() async -> PackStatus {
        #if canImport(Translation)
        if #available(macOS 26.0, *) {
            let a = LanguageAvailability()
            let s1 = await a.status(from: .init(identifier: "hi"), to: .init(identifier: "en"))
            let s2 = await a.status(from: .init(identifier: "en"), to: .init(identifier: "hi"))
            if s1 == .installed && s2 == .installed { return .installed }
            if s1 == .unsupported { return .unsupported }
            return .downloadable
        }
        #endif
        return .unsupported
    }

    static func translate(_ text: String, toHindi: Bool) async -> String? {
        #if canImport(Translation)
        if #available(macOS 26.0, *) {
            let hi = Locale.Language(identifier: "hi"), en = Locale.Language(identifier: "en")
            let (from, to) = toHindi ? (en, hi) : (hi, en)
            guard await LanguageAvailability().status(from: from, to: to) == .installed else { return nil }
            let session = TranslationSession(installedSource: from, target: to)
            return try? await session.translate(text).targetText
        }
        #endif
        return nil
    }
}
