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

    // MARK: the message box

    /// WhatsApp's compose box, found through Accessibility (it has no keyboard shortcut).
    private static func composer() -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        let inputs = AX.inputs(pid: app.processIdentifier)
        return inputs.first { AX.str($0, kAXIdentifierAttribute) == "ChatBar_ComposerTextView" }
            ?? inputs.first { AX.str($0, kAXDescriptionAttribute).localizedCaseInsensitiveContains("compose") }
            ?? inputs.last { AX.str($0, kAXRoleAttribute) == "AXTextArea" }
    }

    private static func text(of e: AXUIElement) -> String { AX.attr(e, kAXValueAttribute) as? String ?? "" }

    /// Click a point on screen, then put the mouse back where it was.
    private static func click(_ p: CGPoint) {
        let back = CGEvent(source: nil)?.location ?? p
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        CGWarpMouseCursorPosition(back)
    }

    private static func actions(_ e: AXUIElement) -> [String] {
        var names: CFArray?
        AXUIElementCopyActionNames(e, &names)
        return names as? [String] ?? []
    }

    /// Chat-list rows are the elements carrying WhatsApp's own row actions (Archive / Pin / Unread).
    private static func isChatRow(_ e: AXUIElement) -> Bool {
        actions(e).contains { $0.contains("Archive") || $0.contains("Pin") }
    }

    private static func walk(_ root: AXUIElement, limit: Int = 6000, _ visit: (AXUIElement) -> Void) {
        var queue = (AX.attr(root, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        var seen = 0
        while !queue.isEmpty && seen < limit {
            let e = queue.removeFirst()
            seen += 1
            visit(e)
            queue += AX.children(e)
        }
    }

    private static func mentions(_ e: AXUIElement, _ q: String) -> Bool {
        [AX.str(e, kAXDescriptionAttribute), AX.str(e, kAXTitleAttribute), AX.attr(e, kAXValueAttribute) as? String ?? ""]
            .contains { $0.lowercased().contains(q) }
    }

    /// After a search, press the top chat row whose name matches `query` (↓/Return don't open results
    /// in the current WhatsApp). Returns false if no matching row shows up.
    private static func openTopResult(_ query: String) async -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return false }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        let q = query.lowercased()
        for _ in 0..<10 {
            var rows: [(AXUIElement, CGRect)] = []
            walk(root) { e in
                if isChatRow(e), mentions(e, q) { rows.append((e, AX.frame(e))) }
            }
            if ProcessInfo.processInfo.environment["PETAGENTS_DEBUG"] == "1" {
                var all = 0
                walk(root) { e in if isChatRow(e) { all += 1 } }
                print("[wa] chat rows:", all, "matching:", rows.count, rows.map { "\($0.1.origin)" })
            }
            if let best = rows.min(by: { $0.1.minY < $1.1.minY }) {
                if ProcessInfo.processInfo.environment["PETAGENTS_DEBUG"] == "1" { print("[wa] pressing row at", best.1) }
                if AXUIElementPerformAction(best.0, kAXPressAction as CFString) != .success {
                    click(CGPoint(x: best.1.minX + min(best.1.width * 0.3, 120), y: best.1.midY))
                }
                return true
            }
            await Mac.sleep(0.3)                  // results are still loading
        }
        return false
    }

    /// True when the chat open on the right is the one we wanted: its header (top of the chat pane,
    /// right of the chat list) shows the name.
    private static func chatIsOpen(_ query: String) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
              let box = composer() else { return false }
        let paneLeft = AX.frame(box).minX - 40
        let q = query.lowercased()
        var found = false
        walk(AXUIElementCreateApplication(app.processIdentifier), limit: 3000) { e in
            if found { return }
            let f = AX.frame(e)
            if f.minX >= paneLeft, f.minY < AX.frame(box).minY - 200, f.height > 0, f.height < 90, !isChatRow(e),
               !AX.inputRoles.contains(AX.str(e, kAXRoleAttribute)), mentions(e, q) { found = true }
        }
        return found
    }

    /// Wait for the open chat's message box and give it keyboard focus.
    private static func focusComposer() async -> AXUIElement? {
        for _ in 0..<16 {
            if let c = composer(), AX.frame(c).width > 0 {
                AXUIElementSetAttributeValue(c, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                await Mac.sleep(0.15)
                if (AX.attr(c, kAXFocusedAttribute) as? Bool) != true {
                    let f = AX.frame(c)
                    click(CGPoint(x: f.midX, y: f.midY))
                    await Mac.sleep(0.2)
                }
                return c
            }
            await Mac.sleep(0.25)                 // the chat is still opening
        }
        return nil
    }

    /// Put `message` in the message box (paste, or set it directly if the paste didn't land).
    private static func write(_ message: String, into c: AXUIElement) async -> Bool {
        if text(of: c).contains(message) { return true }   // already there (click-to-chat link prefilled it)
        await Keyboard.paste(message)
        await Mac.sleep(0.3)
        if text(of: c).contains(message) { return true }
        AXUIElementSetAttributeValue(c, kAXValueAttribute as CFString, message as CFString)
        await Mac.sleep(0.2)
        return text(of: c).contains(message)
    }

    /// Press Return in the message box and check the message actually left it.
    private static func pressSend(_ c: AXUIElement) async -> Bool {
        guard !text(of: c).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        _ = Keyboard.press("return")
        for _ in 0..<8 {
            await Mac.sleep(0.25)
            if text(of: c).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        }
        return false
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
        let forceSearch = ProcessInfo.processInfo.environment["PETAGENTS_WA_SEARCH"] == "1"    // testing the search route
        if target == nil && !forceSearch {
            let r = await contact(named: who)
            target = r.match
            contactsAllowed = r.permission
        }
        if let t = target {
            var comps = URLComponents(string: "whatsapp://send")!
            comps.queryItems = [URLQueryItem(name: "phone", value: t.phone)] + (text.isEmpty ? [] : [URLQueryItem(name: "text", value: text)])
            guard let url = comps.url, NSWorkspace.shared.open(url) else { return .fail("Couldn't open WhatsApp.") }
            if text.isEmpty { return .ok("Opened your WhatsApp chat with \(t.name).") }
            guard Keyboard.allowed(prompt: true) else {
                pending = t.name
                return .ok("Opened \(t.name)'s chat with the message filled in. To let me check it and press send, " +
                           Keyboard.permissionMessage)
            }
            if let err = await Keyboard.focus(app: "WhatsApp") { return err }
            await Mac.sleep(0.8)                    // let the chat finish opening
            guard let box = await focusComposer() else { return .fail("The chat opened, but I couldn't find its message box.") }
            guard await write(text, into: box) else { return .fail("I opened \(t.name)'s chat but couldn't put the message in.") }
            if !send {
                pending = t.name
                return .ok("Wrote it in \(t.name)'s WhatsApp chat. Say \"send it\" when you want it sent.")
            }
            guard await pressSend(box) else {
                pending = t.name
                return .fail("It's written in \(t.name)'s chat but didn't send. Say \"send it\" to try again.")
            }
            pending = nil
            return .ok("Sent \"\(text)\" to \(t.name) on WhatsApp.")
        }

        // 2. Groups / names not in Contacts: WhatsApp's own search. Never auto-sends.
        guard Keyboard.allowed(prompt: true) else { return .fail(Keyboard.permissionMessage) }
        if let err = await Keyboard.focus(app: "WhatsApp") { return err }
        _ = Keyboard.press("escape")                 // close any side panel (contact info, emoji picker…)
        await Mac.sleep(0.3)
        _ = Keyboard.press("cmd+f")
        await Mac.sleep(0.4)
        _ = Keyboard.press("cmd+a")
        await Keyboard.paste(who)
        await Mac.sleep(1.0)                        // results appear as you type
        guard await openTopResult(who) else {
            _ = Keyboard.press("escape")
            return .fail("I searched WhatsApp for \"\(who)\" but found no chat with that name.")
        }
        await Mac.sleep(0.8)
        let note = contactsAllowed ? "" : " (Allow Contacts for Pet Agents and I can open saved contacts exactly.)"
        if text.isEmpty { return .ok("Opened the top WhatsApp search result for \"\(who)\".\(note)") }
        var opened = false
        for _ in 0..<8 where !opened {             // wait for the chosen chat to replace whatever was open
            opened = chatIsOpen(who)
            if !opened { await Mac.sleep(0.25) }
        }
        guard opened, let box = await focusComposer() else {
            return .fail("I searched for \"\(who)\" but couldn't open that chat, so I didn't type anything.")
        }
        guard await write(text, into: box) else { return .fail("The chat opened, but I couldn't put the message in.") }
        pending = who
        let warn = send ? " I found it through search, so I didn't send it:" : ""
        return .ok("Typed it in the chat I found for \"\(who)\".\(warn) check it's the right chat, then say \"send it\".\(note)")
    }

    /// `PetAgents --wa-selftest`: write a line into the open chat's box, check it, clear it. Never sends.
    @MainActor
    static func selfTest() async {
        print("trusted:", AXIsProcessTrusted())
        guard await Keyboard.focus(app: "WhatsApp") == nil else { print("couldn't focus WhatsApp"); return }
        guard let box = await focusComposer() else { print("no message box (no chat open?)"); return }
        let before = text(of: box)
        print("box found, focused:", AX.attr(box, kAXFocusedAttribute) as? Bool ?? false, "starts empty:", before.isEmpty)
        let ok = await write("Pet Agents test (not sent)", into: box)
        print("text landed in box:", ok)
        AXUIElementSetAttributeValue(box, kAXValueAttribute as CFString, before as CFString)
        await Mac.sleep(0.3)
        if !text(of: box).isEmpty && before.isEmpty {         // clear any leftover with select-all + delete
            _ = Keyboard.press("cmd+a"); _ = Keyboard.press("delete")
            await Mac.sleep(0.3)
        }
        print("restored:", text(of: box) == before)
    }

    /// `PetAgents --wa-clear`: empty the open chat's message box (testing).
    @MainActor
    static func clearBox() async {
        guard await Keyboard.focus(app: "WhatsApp") == nil, let box = await focusComposer() else { print("no box"); return }
        _ = Keyboard.press("cmd+a"); _ = Keyboard.press("delete")
        await Mac.sleep(0.3)
        print("box empty:", text(of: box).isEmpty)
    }

    /// "send it": press Return in WhatsApp for the message typed earlier.
    @MainActor
    static func sendPending() async -> ActionResult? {
        guard let who = pending else { return nil }
        guard Keyboard.allowed(prompt: true) else { return .fail(Keyboard.permissionMessage) }
        if let err = await Keyboard.focus(app: "WhatsApp") { return err }
        guard let box = await focusComposer() else { return .fail("I can't find WhatsApp's message box.") }
        guard await pressSend(box) else {
            return .fail("There's nothing in the message box to send (or WhatsApp didn't send it).")
        }
        pending = nil
        return .ok("Sent it to \(who) on WhatsApp.")
    }
}
