import AppKit
import ApplicationServices

/// Accessibility helpers for apps whose controls have no keyboard shortcut (e.g. WhatsApp's message box).
enum AX {
    static func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }
    static func str(_ e: AXUIElement, _ name: String) -> String { attr(e, name) as? String ?? "" }
    static func children(_ e: AXUIElement) -> [AXUIElement] { attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] }

    static func frame(_ e: AXUIElement) -> CGRect {
        var p = CGPoint.zero, s = CGSize.zero
        if let v = attr(e, kAXPositionAttribute) { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
        if let v = attr(e, kAXSizeAttribute) { AXValueGetValue(v as! AXValue, .cgSize, &s) }
        return CGRect(origin: p, size: s)
    }

    static let inputRoles: Set<String> = ["AXTextArea", "AXTextField", "AXSearchField", "AXComboBox"]

    /// Every text-input element in the app's windows (breadth-first, bounded).
    static func inputs(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var queue = (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        var out: [AXUIElement] = []
        var seen = 0
        while !queue.isEmpty && seen < 4000 {
            let e = queue.removeFirst()
            seen += 1
            if inputRoles.contains(str(e, kAXRoleAttribute)) { out.append(e) }
            queue += children(e)
        }
        return out
    }

    /// `PetAgents --ax-inputs <bundle id>`: list an app's text inputs (no contents) and what has focus.
    static func dump(bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            print("not running: \(bundleID)"); return
        }
        print("trusted:", AXIsProcessTrusted())
        let wins = (attr(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute) as? [AXUIElement]) ?? []
        print("windows:", wins.count, wins.map { "\(str($0, kAXSubroleAttribute)) \(frame($0).size)" })
        for e in inputs(pid: app.processIdentifier) {
            let value = attr(e, kAXValueAttribute) as? String ?? ""
            print("- \(str(e, kAXRoleAttribute)) sub=\(str(e, kAXSubroleAttribute)) placeholder=\"\(str(e, kAXPlaceholderValueAttribute))\" " +
                  "desc=\"\(str(e, kAXDescriptionAttribute))\" id=\"\(str(e, kAXIdentifierAttribute))\" frame=\(frame(e)) " +
                  "focused=\(attr(e, kAXFocusedAttribute) as? Bool ?? false) valueLength=\(value.count)")
        }
        let sys = AXUIElementCreateApplication(app.processIdentifier)
        if let f = attr(sys, kAXFocusedUIElementAttribute) {
            let fe = f as! AXUIElement
            print("focused element:", str(fe, kAXRoleAttribute), "placeholder=\"\(str(fe, kAXPlaceholderValueAttribute))\"")
        } else { print("focused element: none") }
    }
}
