import AppKit
import ImageIO

struct AnimMeta: Decodable {
    let frames: Int
    let w: Int
    let h: Int
    let anchorX: Double
    let loops: Int
    let moving: Bool
    let label: String
    let kind: String   // base | idle | jutsu
}

struct PetMeta: Decodable {
    let id: String
    let name: String
    let era: String
    let color: String
    let tagline: String
    let speed: Double
    let group: String
    let animations: [String: AnimMeta]

    var displayName: String {
        switch era {
        case "classic": return "\(name) (Part I)"
        case "shippuden": return "\(name) (Shippuden)"
        default: return name
        }
    }
    var shortName: String { name.components(separatedBy: " ").first ?? name }

    func ids(kind: String) -> [String] {
        animations.filter { $0.value.kind == kind }.map(\.key).sorted {
            animations[$0]!.label < animations[$1]!.label
        }
    }
}

enum Assets {
    /// Folder holding manifest.js and strips/: the app bundle's Resources, or ../preview when run from the repo.
    static let root: URL = locate()
    static let pets: [PetMeta] = loadManifest()
    static let byId: [String: PetMeta] = Dictionary(uniqueKeysWithValues: pets.map { ($0.id, $0) })

    private static func locate() -> URL {
        let fm = FileManager.default
        if let r = Bundle.main.resourceURL, fm.fileExists(atPath: r.appendingPathComponent("manifest.js").path) {
            return r
        }
        let starts = [
            URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent(),
            URL(fileURLWithPath: fm.currentDirectoryPath),
        ]
        for start in starts {
            var dir = start
            for _ in 0..<8 {
                let p = dir.appendingPathComponent("preview")
                if fm.fileExists(atPath: p.appendingPathComponent("manifest.js").path) { return p }
                dir = dir.deletingLastPathComponent()
            }
        }
        fatalError("Pet Agents: can't find manifest.js / strips. Build the app with app/build.sh.")
    }

    private static func loadManifest() -> [PetMeta] {
        guard let js = try? String(contentsOf: root.appendingPathComponent("manifest.js"), encoding: .utf8),
              let a = js.firstIndex(of: "["), let b = js.lastIndex(of: "]") else { return [] }
        let json = Data(js[a...b].utf8)
        return (try? JSONDecoder().decode([PetMeta].self, from: json)) ?? []
    }
}

/// Decoded animation frames. Walk/idle/drag stay loaded; jutsu strips are dropped when they finish.
final class SpriteCache {
    static let shared = SpriteCache()
    private var cache: [String: [String: [CGImage]]] = [:]   // pet -> anim -> frames

    func frames(_ pet: String, _ anim: String, _ meta: AnimMeta) -> [CGImage] {
        if let f = cache[pet]?[anim] { return f }
        let out = Self.load(pet, anim, meta)
        cache[pet, default: [:]][anim] = out
        return out
    }

    /// Decode frames without caching them (used for thumbnails and hover previews).
    static func load(_ pet: String, _ anim: String, _ meta: AnimMeta, limit: Int? = nil) -> [CGImage] {
        let url = Assets.root.appendingPathComponent("strips/\(pet)_\(anim).png")
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let strip = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return [] }
        var out: [CGImage] = []
        for i in 0..<min(meta.frames, limit ?? meta.frames) {
            if let f = decodeFrame(strip, CGRect(x: i * meta.w, y: 0, width: meta.w, height: meta.h)) { out.append(f) }
        }
        return out
    }

    func release(_ pet: String, _ anim: String) {
        if ["walk", "front", "drag"].contains(anim) { return }
        cache[pet]?[anim] = nil
    }

    func releaseAll(_ pet: String) { cache[pet] = nil }

    private static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Each frame becomes its own bitmap in the format Core Animation uses natively (sRGB, BGRA,
    /// premultiplied), so showing a frame never needs a decode or colour conversion.
    private static func decodeFrame(_ strip: CGImage, _ rect: CGRect) -> CGImage? {
        guard let crop = strip.cropping(to: rect),
              let ctx = CGContext(data: nil, width: Int(rect.width), height: Int(rect.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: srgb,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(crop, in: CGRect(origin: .zero, size: rect.size))
        return ctx.makeImage()
    }
}
