import AppKit
import Carbon.HIToolbox

// MARK: - command bar

final class CommandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { CommandBar.shared.hide(restoreFocus: true) }
}

/// The text box that pops up above a pet when you click it (or press ⌃⌥Space).
final class CommandBar: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    static let shared = CommandBar()

    private let panel: CommandPanel
    private let field = NSTextField()
    private weak var pet: Pet?
    private var previousApp: NSRunningApplication?
    private var history: [String] = []
    private var historyIndex = 0

    private override init() {
        panel = CommandPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 46),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let bg = NSVisualEffectView(frame: panel.contentView!.bounds)
        bg.material = .hudWindow
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 12
        bg.layer?.masksToBounds = true
        bg.autoresizingMask = [.width, .height]
        panel.contentView = bg

        field.frame = NSRect(x: 14, y: 11, width: 352, height: 24)
        field.autoresizingMask = [.width]
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 15)
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        bg.addSubview(field)
    }

    func show(for pet: Pet) {
        self.pet = pet
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        field.stringValue = ""
        field.placeholderString = "Give \(pet.meta.shortName) a mission… e.g. play Blinding Lights"
        historyIndex = history.count

        let size = panel.frame.size
        let head = pet.headTop
        let s = Desktop.shared.screen(containingX: head.x, y: head.y - 10).visibleFrame
        var o = NSPoint(x: head.x - size.width / 2, y: head.y + 8)
        if pet.bubble.visible { o.y += 40 }
        o.x = min(max(o.x, s.minX + 8), s.maxX - size.width - 8)
        o.y = min(max(o.y, s.minY + 8), s.maxY - size.height - 8)
        panel.setFrameOrigin(o)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    func hide(restoreFocus: Bool) {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        if restoreFocus { previousApp?.activate() }
    }

    func windowDidResignKey(_ notification: Notification) { hide(restoreFocus: false) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.insertNewline(_:)):
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            hide(restoreFocus: true)
            if !text.isEmpty, let pet {
                if history.last != text { history.append(text) }
                Agent.shared.handle(text, pet: pet)
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            hide(restoreFocus: true)
            return true
        case #selector(NSResponder.moveUp(_:)):
            if historyIndex > 0 { historyIndex -= 1; field.stringValue = history[historyIndex] }
            return true
        case #selector(NSResponder.moveDown(_:)):
            if historyIndex < history.count - 1 { historyIndex += 1; field.stringValue = history[historyIndex] }
            else { historyIndex = history.count; field.stringValue = "" }
            return true
        default:
            return false
        }
    }
}

// MARK: - settings

final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?
    private let key = NSSecureTextField()
    private let model = NSTextField()
    private let spotifyId = NSTextField()
    private let spotifySecret = NSSecureTextField()
    private let webSearch = NSButton(checkboxWithTitle: "Let the agent search the web (finds Spotify links without Spotify keys)",
                                     target: nil, action: nil)

    func show() {
        if window == nil { build() }
        let c = App.config
        key.stringValue = c.anthropicKey
        model.stringValue = c.model
        spotifyId.stringValue = c.spotifyClientId
        spotifySecret.stringValue = c.spotifyClientSecret
        webSearch.state = c.webSearch ? .on : .off
        NSApp.activate(ignoringOtherApps: true)
        window!.center()
        window!.makeKeyAndOrderFront(nil)
    }

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.alignment = .right
        return l
    }

    private func note(_ s: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: s)
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        l.preferredMaxLayoutWidth = 360
        return l
    }

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 330), styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = "Shinobi Pets Settings"
        w.isReleasedWhenClosed = false
        w.delegate = self
        for f in [key, model, spotifyId, spotifySecret] as [NSTextField] {
            f.widthAnchor.constraint(equalToConstant: 360).isActive = true
        }
        key.placeholderString = "sk-ant-…  (or set ANTHROPIC_API_KEY)"
        model.placeholderString = "claude-opus-5-5"
        spotifyId.placeholderString = "optional"
        spotifySecret.placeholderString = "optional"

        let empty = NSView()
        let grid = NSGridView(views: [
            [label("Anthropic API key"), key],
            [empty, note("Lets your ninja understand any command. Get one at console.anthropic.com. Without it, only simple phrasings work.")],
            [label("Model"), model],
            [label("Spotify Client ID"), spotifyId],
            [label("Spotify Client Secret"), spotifySecret],
            [NSView(), note("Optional: makes song search exact. Create an app at developer.spotify.com/dashboard and copy its Client ID and Secret.")],
            [NSView(), webSearch],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false

        let save = NSButton(title: "Save", target: self, action: #selector(saveClicked))
        save.keyEquivalent = "\r"
        save.translatesAutoresizingMaskIntoConstraints = false
        let content = w.contentView!
        content.addSubview(grid)
        content.addSubview(save)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            save.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 16),
            save.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            save.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
        window = w
    }

    @objc private func saveClicked() {
        App.config.anthropicKey = key.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = model.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        App.config.model = m.isEmpty ? "claude-opus-5-5" : m
        App.config.spotifyClientId = spotifyId.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        App.config.spotifyClientSecret = spotifySecret.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        App.config.webSearch = webSearch.state == .on
        App.config.save()
        MainActor.assumeIsolated { Agent.shared.resetConversation() }
        window?.close()
        App.delegate.anyPet()?.say(App.config.apiKey.isEmpty ? "Saved! (Offline mode: no API key.)" : "Saved! Ready for missions. 🍥")
    }
}

// MARK: - global hotkey (⌃⌥Space)

enum HotKey {
    static var handler: (() -> Void)?
    private static var ref: EventHotKeyRef?

    static func register(_ handler: @escaping () -> Void) {
        self.handler = handler
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.handler?() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x5348_4E42), id: 1)   // 'SHNB'
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
    }
}
