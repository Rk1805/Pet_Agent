import AppKit
import Contacts

/// WhatsApp desktop: open a chat by contact name / number / group, put a message in it, and send it
/// only when asked.
///
/// Saved contacts with a phone number go through the official click-to-chat link
/// (whatsapp://send?phone=…&text=…), which opens exactly that chat with the text filled in.
/// Anything else (groups, names not in Contacts) uses WhatsApp's own search (⌘F); because search can
/// land on the wrong chat, that path never sends by itself.
enum WhatsApp {
    static let bundleID = "net.whatsapp.WhatsApp"

    static var installed: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil }

    /// The chat we last typed into without sending, so "send it" knows where to press Return.
    @MainActor static var pending: String?

    // MARK: contacts

    private static func digits(_ s: String) -> String { s.filter { $0.isNumber } }

    /// Country calling code for numbers saved without one (from the Mac's region).
    private static var defaultCountryCode: String {
        let codes = ["IN": "91", "US": "1", "CA": "1", "GB": "44", "AU": "61", "AE": "971", "SG": "65", "DE": "49",
                     "FR": "33", "ES": "34", "IT": "39", "NL": "31", "PK": "92", "BD": "880", "NP": "977", "LK": "94",
                     "SA": "966", "NZ": "64", "ZA": "27", "BR": "55", "MX": "52", "JP": "81", "ID": "62", "MY": "60"]
        return codes[Locale.current.region?.identifier ?? "IN"] ?? "91"
    }

    /// "+91 98765 43210" → "919876543210"; "098765 43210" / "98765 43210" → country code + number.
    static func international(_ raw: String) -> String? {
        let hasPlus = raw.trimmingCharacters(in: .whitespaces).hasPrefix("+") || raw.hasPrefix("00")
        var d = digits(raw)
        if d.hasPrefix("00") { d.removeFirst(2) }
        guard d.count >= 7 else { return nil }
        if hasPlus { return d }
        if d.hasPrefix("0") { d.removeFirst() }
        let cc = defaultCountryCode
        return d.count <= 10 ? cc + d : d
    }

    struct Match { let name: String; let phone: String }

    /// Find a saved contact by name ("mom", "Rahul Sharma") and their mobile number.
    static func contact(named query: String) async -> (match: Match?, permission: Bool) {
        let store = CNContactStore()
        let ok: Bool = await withCheckedContinuation { c in store.requestAccess(for: .contacts) { granted, _ in c.resume(returning: granted) } }
        guard ok else { return (nil, false) }
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactOrganizationNameKey,
                    CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let found = (try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: query), keysToFetch: keys)) ?? []
        let q = query.lowercased()
        func full(_ c: CNContact) -> String { [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ") }
        let ranked = found.filter { !$0.phoneNumbers.isEmpty }.sorted { a, b in
            func score(_ c: CNContact) -> Int {
                let n = full(c).lowercased()
                if n == q || c.nickname.lowercased() == q { return 0 }
                if n.hasPrefix(q) { return 1 }
                return 2
            }
            return score(a) < score(b)
        }
        guard let c = ranked.first else { return (nil, true) }
        let mobile = c.phoneNumbers.first { [CNLabelPhoneNumberMobile, CNLabelPhoneNumberiPhone].contains($0.label ?? "") }
            ?? c.phoneNumbers.first!
        guard let phone = international(mobile.value.stringValue) else { return (nil, true) }
        let name = full(c).isEmpty ? (c.nickname.isEmpty ? c.organizationName : c.nickname) : full(c)
        return (Match(name: name, phone: phone), true)
    }

    // MARK: actions

    /// Open a chat and optionally put `text` in it; press Return only when `send` is true.
    @MainActor
    static func message(chat: String, text: String, send: Bool) async -> ActionResult {
        guard installed else { return .fail("WhatsApp isn't installed. Get it from the Mac App Store.") }
        let who = chat.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !who.isEmpty else { return .fail("Which chat? Say a contact or group name.") }

        // 1. A number, or a saved contact with a number: exact chat via click-to-chat.
        var target: Match?
        if who.filter(\.isNumber).count >= 7, let phone = international(who) { target = Match(name: who, phone: phone) }
        var contactsAllowed = true
        if target == nil {
            let r = await contact(named: who)
            target = r.match
            contactsAllowed = r.permission
        }
        if let t = target {
            var comps = URLComponents(string: "whatsapp://send")!
            comps.queryItems = [URLQueryItem(name: "phone", value: t.phone)] + (text.isEmpty ? [] : [URLQueryItem(name: "text", value: text)])
            guard let url = comps.url, NSWorkspace.shared.open(url) else { return .fail("Couldn't open WhatsApp.") }
            if text.isEmpty { return .ok("Opened your WhatsApp chat with \(t.name).") }
            if !send {
                pending = t.name
                return .ok("Wrote it in \(t.name)'s WhatsApp chat. Say \"send it\" when you want it sent.")
            }
            guard Keyboard.allowed(prompt: true) else {
                pending = t.name
                return .fail("It's written in \(t.name)'s chat, but I need Accessibility permission to press send. " + Keyboard.permissionMessage)
            }
            if let err = await Keyboard.focus(app: "WhatsApp") { return err }
            await Mac.sleep(1.2)                    // let the chat finish opening
            _ = Keyboard.press("return")
            pending = nil
            return .ok("Sent \"\(text)\" to \(t.name) on WhatsApp.")
        }

        // 2. Groups / names not in Contacts: WhatsApp's own search. Never auto-sends.
        guard Keyboard.allowed(prompt: true) else { return .fail(Keyboard.permissionMessage) }
        if let err = await Keyboard.focus(app: "WhatsApp") { return err }
        _ = Keyboard.press("cmd+f")
        await Mac.sleep(0.4)
        _ = Keyboard.press("cmd+a")
        await Keyboard.paste(who)
        await Mac.sleep(1.4)                        // results appear as you type
        _ = Keyboard.press("down")
        await Mac.sleep(0.3)
        _ = Keyboard.press("return")
        await Mac.sleep(1.0)
        let note = contactsAllowed ? "" : " (Allow Contacts for Pet Agents and I can open saved contacts exactly.)"
        if text.isEmpty { return .ok("Opened the top WhatsApp search result for \"\(who)\".\(note)") }
        await Keyboard.paste(text)
        pending = who
        let warn = send ? " I found it through search, so I didn't send it:" : ""
        return .ok("Typed it in the chat I found for \"\(who)\".\(warn) check it's the right chat, then say \"send it\".\(note)")
    }

    /// "send it": press Return in WhatsApp for the message typed earlier.
    @MainActor
    static func sendPending() async -> ActionResult? {
        guard let who = pending else { return nil }
        guard Keyboard.allowed(prompt: true) else { return .fail(Keyboard.permissionMessage) }
        if let err = await Keyboard.focus(app: "WhatsApp") { return err }
        _ = Keyboard.press("return")
        pending = nil
        return .ok("Sent it to \(who) on WhatsApp.")
    }
}
