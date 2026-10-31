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
        MainActor.assumeIsolated { Agent.shared.prewarm(pet) }
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
        let id = EventHotKeyID(signature: OSType(0x5054_4147), id: 1)   // 'PTAG'
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
    }
}
