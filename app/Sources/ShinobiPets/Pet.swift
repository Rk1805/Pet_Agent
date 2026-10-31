import AppKit
import QuartzCore

let BASE: CGFloat = 192
let FRAME_TIME = 0.1   // 10 fps

/// Borderless, transparent, always-on-top window that holds one pet sprite.
/// It ignores the mouse except while the cursor is over the pet's body, so clicks pass through to your apps.
final class PetWindow: NSWindow {
    let sprite = CALayer()

    init(pet: Pet) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: .borderless,
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let view = PetView(pet: pet)
        view.wantsLayer = true
        contentView = view
        sprite.frame = view.bounds
        sprite.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        sprite.magnificationFilter = .nearest
        sprite.minificationFilter = .nearest
        sprite.contentsGravity = .resize
        sprite.actions = ["contents": NSNull(), "transform": NSNull(), "bounds": NSNull(), "position": NSNull()]
        view.layer?.addSublayer(sprite)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PetView: NSView {
    weak var pet: Pet?
    init(pet: Pet) { self.pet = pet; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { pet?.pressBegan(NSEvent.mouseLocation) }
    override func mouseDragged(with event: NSEvent) { pet?.pressMoved(NSEvent.mouseLocation) }
    override func mouseUp(with event: NSEvent) { pet?.pressEnded() }
    override func rightMouseDown(with event: NSEvent) {
        guard let pet else { return }
        NSMenu.popUpContextMenu(pet.contextMenu(), with: event, for: self)
    }
}

final class Pet {
    let meta: PetMeta
    private(set) var window: PetWindow!
    let bubble = SpeechBubble()

    var x: CGFloat              // left edge of the 192×192 base frame (global Cocoa coordinates)
    var y: CGFloat              // feet
    var vy: CGFloat = 0
    var dir: CGFloat = 1
    private(set) var anim = "walk"
    private var frame = 0
    private var framesLeft = 0
    private var acc = 0.0
    private var walkFor = 4.0
    private var platformKey: String?
    private var platformX0: CGFloat = 0

    private var press: NSPoint?
    private(set) var dragging = false
    private(set) var busy = false
    private var hovering = false
    private var lastFrameRect = NSRect.zero
    private var lastFlip: CGFloat = 0

    var scale: CGFloat { CGFloat(App.config.scale) }
    var fw: CGFloat { BASE * scale }
    var a: AnimMeta { meta.animations[anim] ?? meta.animations["walk"]! }
    var speed: CGFloat { (30 + CGFloat(meta.speed) * 80) * scale }
    var headTop: NSPoint { NSPoint(x: x + fw / 2, y: y + fw * 0.92) }

    init(meta: PetMeta, x: CGFloat? = nil) {
        self.meta = meta
        let s = NSScreen.main ?? NSScreen.screens[0]
        let vf = s.visibleFrame
        self.x = x ?? CGFloat.random(in: vf.minX + 20...max(vf.minX + 21, vf.maxX - 220))
        self.y = vf.maxY - 40
        self.dir = Bool.random() ? 1 : -1
        self.walkFor = Double.random(in: 2...6)
        window = PetWindow(pet: self)
        layout()
        window.orderFrontRegardless()
    }

    func remove() {
        bubble.hide()
        window.orderOut(nil)
        SpriteCache.shared.releaseAll(meta.id)
    }

    // MARK: animation control

    func play(_ id: String, loops: Int? = nil) {
        guard let m = meta.animations[id] else { return }
        if anim != id { SpriteCache.shared.release(meta.id, anim) }
        anim = id; frame = 0; acc = 0
        framesLeft = m.frames * (loops ?? m.loops)
    }

    func walk() {
        play("walk")
        walkFor = Double.random(in: 3...8)
        if Double.random(in: 0...1) < 0.3 { dir *= -1 }
    }

    private func choose() -> String {
        let jutsu = meta.ids(kind: "jutsu"), idle = meta.ids(kind: "idle")
        let r = Double.random(in: 0...1)
        if r < 0.35, let j = jutsu.randomElement() { return j }
        if r < 0.55, let i = idle.randomElement() { return i }
        if r < 0.70 { return "sleep" }
        return "front"
    }

    func randomJutsu() { if let j = meta.ids(kind: "jutsu").randomElement() { play(j) } }

    // MARK: agent hooks

    func startWorking(_ status: String) {
        busy = true
        play("front", loops: 1000)
        say(status, seconds: 60)
    }

    func status(_ text: String) { if busy { say(text, seconds: 60) } }

    func finishWorking(_ reply: String, success: Bool) {
        busy = false
        say(reply, seconds: max(4, min(14, Double(reply.count) * 0.07)))
        if success, !dragging { randomJutsu() } else if !dragging { play("front") }
    }

    func say(_ text: String, seconds: Double = 5) {
        bubble.show(text, seconds: seconds)
        bubble.position(above: headTop)
    }

    // MARK: simulation

    func step(_ dt: Double) {
        let desk = Desktop.shared
        if dragging {
            advanceFrames(dt, looping: true)
            return
        }
        // Gravity, landing on window tops / the floor.
        if let key = platformKey, let p = desk.platform(key) {
            if !p.isFloor { x += p.x0 - platformX0 }      // ride along when the window is dragged
            platformX0 = p.x0
            y = p.y
            if !desk.standable(p, x: x + fw / 2) { platformKey = nil }   // walked off the edge or got covered
        } else {
            platformKey = nil
            let prevY = y
            vy = max(vy - 1800 * CGFloat(dt), -1400)
            y += vy * CGFloat(dt)
            let cx = x + fw / 2
            for p in desk.platforms where prevY >= p.y - 1 && y <= p.y && desk.standable(p, x: cx) {
                y = p.y; vy = 0; platformKey = p.key; platformX0 = p.x0
                break
            }
            if y < desk.lowestY - 400 { respawn() }
        }
        // Walking.
        let walking = (anim == "walk" || a.moving) && !busy
        if walking && platformKey != nil {
            x += dir * speed * (a.moving ? 2.6 : 1) * CGFloat(dt)
            let s = desk.screen(containingX: x + fw / 2, y: y + 1).frame
            if x < s.minX { x = s.minX; dir = 1 }
            if x > s.maxX - fw { x = s.maxX - fw; dir = -1 }
        }
        advanceFrames(dt, looping: anim == "walk")
        if anim == "walk" && platformKey != nil && !busy {
            walkFor -= dt
            if walkFor <= 0 { play(choose()) }
        }
    }

    private func advanceFrames(_ dt: Double, looping: Bool) {
        acc += dt
        while acc >= FRAME_TIME {
            acc -= FRAME_TIME
            frame = (frame + 1) % max(1, a.frames)
            if !looping && !dragging {
                framesLeft -= 1
                if framesLeft <= 0 {
                    if busy { play("front", loops: 1000) } else { walk() }
                }
            }
        }
    }

    private func respawn() {
        let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        x = CGFloat.random(in: vf.minX + 20...max(vf.minX + 21, vf.maxX - fw - 20))
        y = vf.maxY - 20; vy = 0
    }

    /// Place the window around the current animation canvas and show the current frame.
    func layout() {
        let a = self.a
        let frames = SpriteCache.shared.frames(meta.id, anim, a)
        let w = CGFloat(a.w) * scale, h = CGFloat(a.h) * scale
        let cx = x + fw / 2
        var left = x - CGFloat(a.anchorX) * scale
        if dir < 0 { left = 2 * cx - (left + w) }   // mirror the canvas around the pet's centre
        let rect = NSRect(x: left.rounded(), y: y.rounded(), width: w.rounded(), height: h.rounded())
        if rect.size != lastFrameRect.size { window.setFrame(rect, display: false) }
        else if rect.origin != lastFrameRect.origin { window.setFrameOrigin(rect.origin) }
        lastFrameRect = rect
        if !frames.isEmpty { window.sprite.contents = frames[min(frame, frames.count - 1)] }
        if dir != lastFlip {
            window.sprite.setAffineTransform(dir < 0 ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
            lastFlip = dir
        }
        if bubble.visible { bubble.position(above: headTop) }
    }

    // MARK: mouse

    var hitRect: NSRect { NSRect(x: x + fw * 0.3, y: y, width: fw * 0.4, height: fw * 0.92) }

    func updateMouse(_ m: NSPoint) {
        let over = dragging || press != nil || hitRect.contains(m)
        if over != hovering {
            hovering = over
            window.ignoresMouseEvents = !over
        }
    }

    func pressBegan(_ m: NSPoint) { press = m; App.delegate.activePet = self }

    func pressMoved(_ m: NSPoint) {
        guard let p = press else { return }
        if !dragging && hypot(m.x - p.x, m.y - p.y) > 4 {
            dragging = true; platformKey = nil
            play("drag")
        }
        if dragging { x = m.x - fw / 2; y = m.y - fw * 0.8 }
    }

    func pressEnded() {
        defer { press = nil }
        if dragging {
            dragging = false; vy = 0
            if busy { play("front", loops: 1000) } else { walk() }
        } else {
            App.delegate.openCommandBar(for: self)
        }
    }

    func contextMenu() -> NSMenu {
        App.delegate.activePet = self
        let menu = NSMenu(title: meta.displayName)
        let title = NSMenuItem(title: meta.displayName, action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(ClosureItem("💬 Give a Mission…") { [weak self] in
            guard let self else { return }
            App.delegate.openCommandBar(for: self)
        })
        menu.addItem(.separator())
        for id in meta.ids(kind: "jutsu") {
            menu.addItem(ClosureItem("🌀 " + meta.animations[id]!.label) { [weak self] in self?.play(id) })
        }
        menu.addItem(.separator())
        for id in meta.ids(kind: "idle") + ["sleep", "front"] where meta.animations[id] != nil {
            menu.addItem(ClosureItem(meta.animations[id]!.label) { [weak self] in self?.play(id) })
        }
        menu.addItem(ClosureItem("Walk") { [weak self] in self?.walk() })
        menu.addItem(.separator())
        menu.addItem(ClosureItem("Dismiss") { [weak self] in
            guard let self else { return }
            App.delegate.dismiss(self.meta.id)
        })
        return menu
    }
}

/// NSMenuItem that runs a closure.
final class ClosureItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, key: String = "", _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}

// MARK: - speech bubble

final class SpeechBubble {
    private var window: NSWindow?
    private var view: BubbleView?
    private var hideWork: DispatchWorkItem?
    private(set) var visible = false

    func show(_ text: String, seconds: Double) {
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = true
            w.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            let v = BubbleView()
            w.contentView = v
            window = w; view = v
        }
        view!.text = text
        window!.setContentSize(view!.fittingSizeForText())
        view!.needsDisplay = true
        window!.orderFrontRegardless()
        visible = true
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        window?.orderOut(nil)
        visible = false
    }

    func position(above p: NSPoint) {
        guard let w = window else { return }
        let size = w.frame.size
        var o = NSPoint(x: (p.x - size.width / 2).rounded(), y: p.y.rounded())
        let s = Desktop.shared.screen(containingX: p.x, y: p.y - 10).visibleFrame
        o.x = min(max(o.x, s.minX + 4), s.maxX - size.width - 4)
        o.y = min(o.y, s.maxY - size.height)
        if w.frame.origin != o { w.setFrameOrigin(o) }
    }
}

final class BubbleView: NSView {
    var text = ""
    private let pad = NSSize(width: 12, height: 8)
    private let tail: CGFloat = 8
    private let maxWidth: CGFloat = 260
    private var attrs: [NSAttributedString.Key: Any] {
        let para = NSMutableParagraphStyle(); para.alignment = .left; para.lineBreakMode = .byWordWrapping
        return [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.black, .paragraphStyle: para]
    }

    func fittingSizeForText() -> NSSize {
        let r = (text as NSString).boundingRect(with: NSSize(width: maxWidth, height: 2000),
                                                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
        return NSSize(width: ceil(r.width) + pad.width * 2, height: ceil(r.height) + pad.height * 2 + tail)
    }

    override func draw(_ dirtyRect: NSRect) {
        let body = NSRect(x: 0.5, y: tail + 0.5, width: bounds.width - 1, height: bounds.height - tail - 1)
        let path = NSBezierPath(roundedRect: body, xRadius: 10, yRadius: 10)
        let mid = bounds.midX
        let t = NSBezierPath()
        t.move(to: NSPoint(x: mid - 7, y: tail + 1))
        t.line(to: NSPoint(x: mid, y: 0.5))
        t.line(to: NSPoint(x: mid + 7, y: tail + 1))
        t.close()
        NSColor(white: 1, alpha: 0.97).setFill()
        path.fill(); t.fill()
        NSColor(white: 0, alpha: 0.25).setStroke()
        path.lineWidth = 1; path.stroke()
        (text as NSString).draw(in: NSRect(x: pad.width, y: tail + pad.height, width: bounds.width - pad.width * 2,
                                           height: bounds.height - tail - pad.height * 2), withAttributes: attrs)
    }
}
