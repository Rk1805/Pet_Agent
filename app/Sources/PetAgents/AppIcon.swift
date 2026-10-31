import AppKit

/// The app icon, drawn from the pet sprites: a night-sky tile with Naruto standing on it.
enum AppIcon {
    static func png(size: Int = 1024) -> Data? {
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let s = CGFloat(size)
        let inset = s * 0.1, rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
        let path = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.width * 0.225, transform: nil)
        ctx.addPath(path)
        ctx.clip()
        let colors = [CGColor(srgbRed: 0.31, green: 0.60, blue: 0.63, alpha: 1), CGColor(srgbRed: 0.04, green: 0.06, blue: 0.24, alpha: 1)]
        let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors as CFArray, locations: [0, 0.75])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
        ctx.setFillColor(CGColor(srgbRed: 0.55, green: 0.53, blue: 1, alpha: 0.25))
        ctx.fillEllipse(in: CGRect(x: rect.midX - s * 0.2, y: rect.midY + s * 0.05, width: s * 0.4, height: s * 0.22))
        if let m = Assets.byId["naruto"], let a = m.animations["front"], let f = SpriteCache.load(m.id, "front", a, limit: 1).first {
            ctx.interpolationQuality = .none
            let side = rect.width * 0.95
            ctx.draw(f, in: CGRect(x: rect.midX - side / 2, y: rect.minY - side * 0.02, width: side, height: side))
        }
        guard let img = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])
    }
}
