import AppKit
import CoreGraphics

/// Something a pet can stand on: the top edge of a real window, or the floor of a screen (top of the Dock).
struct Platform {
    let key: String          // "w<windowID>" or "s<screen index>"
    let x0: CGFloat
    let x1: CGFloat
    let y: CGFloat           // Cocoa coordinates (origin bottom-left of the main screen)
    let order: Int           // index in the front-to-back window list; -1 for floors
    var isFloor: Bool { order < 0 }
}

/// Snapshot of the real desktop: on-screen windows of other apps, read with CGWindowList.
/// Only window bounds are used, so no Screen Recording permission is needed.
final class Desktop {
    static let shared = Desktop()

    private(set) var platforms: [Platform] = []      // sorted highest first
    private var windowRects: [CGRect] = []            // front to back
    private var byKey: [String: Platform] = [:]
    private(set) var lowestY: CGFloat = 0
    private var lastRefresh: CFTimeInterval = 0

    func refreshIfNeeded(_ now: CFTimeInterval) {
        if now - lastRefresh >= 0.2 { refresh(); lastRefresh = now }
    }

    func refresh() {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return }
        let primaryH = primary.frame.height
        let me = ProcessInfo.processInfo.processIdentifier

        var rects: [CGRect] = []
        var list: [Platform] = []
        let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                    as? [[String: Any]]) ?? []
        for w in info {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int32) != me,
                  let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let cg = CGRect(dictionaryRepresentation: bd as CFDictionary),
                  let num = w[kCGWindowNumber as String] as? Int else { continue }
            if let alpha = w[kCGWindowAlpha as String] as? Double, alpha < 0.05 { continue }
            if cg.width < 120 || cg.height < 60 { continue }
            let r = CGRect(x: cg.minX, y: primaryH - cg.maxY, width: cg.width, height: cg.height)
            let order = rects.count
            rects.append(r)
            // Skip windows whose top is tucked under the menu bar (maximised / full-height windows).
            if let s = screens.first(where: { $0.frame.contains(CGPoint(x: r.midX, y: r.maxY - 1)) }),
               r.maxY > s.visibleFrame.maxY - 30 { continue }
            list.append(Platform(key: "w\(num)", x0: r.minX, x1: r.maxX, y: r.maxY, order: order))
        }
        for (i, s) in screens.enumerated() {
            list.append(Platform(key: "s\(i)", x0: s.frame.minX, x1: s.frame.maxX, y: s.visibleFrame.minY, order: -1))
        }
        list.sort { $0.y > $1.y }
        windowRects = rects
        platforms = list
        byKey = Dictionary(list.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        lowestY = screens.map(\.frame.minY).min() ?? 0
    }

    func platform(_ key: String) -> Platform? { byKey[key] }

    /// A window top is usable at x only if no window in front of it covers that spot.
    func standable(_ p: Platform, x: CGFloat) -> Bool {
        if x < p.x0 || x > p.x1 { return false }
        if p.isFloor { return true }
        let pt = CGPoint(x: x, y: p.y + 4)
        for j in 0..<min(p.order, windowRects.count) where windowRects[j].contains(pt) { return false }
        return NSScreen.screens.contains { $0.frame.contains(CGPoint(x: x, y: p.y - 1)) }
    }

    func screen(containingX x: CGFloat, y: CGFloat) -> NSScreen {
        let pt = CGPoint(x: x, y: y)
        return NSScreen.screens.first { $0.frame.contains(pt) }
            ?? NSScreen.screens.first { x >= $0.frame.minX && x < $0.frame.maxX }
            ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
