import Foundation

/// Settings saved in ~/Library/Application Support/ShinobiPets/config.json (readable only by you).
struct Config: Codable {
    var spotifyClientId = ""
    var spotifyClientSecret = ""
    var scale = 0.75
    var pets = ["naruto", "kakashi"]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        spotifyClientId = try c.decodeIfPresent(String.self, forKey: .spotifyClientId) ?? d.spotifyClientId
        spotifyClientSecret = try c.decodeIfPresent(String.self, forKey: .spotifyClientSecret) ?? d.spotifyClientSecret
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? d.scale
        pets = try c.decodeIfPresent([String].self, forKey: .pets) ?? d.pets
    }

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShinobiPets", isDirectory: true)
    }
    static var url: URL { directory.appendingPathComponent("config.json") }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: url),
              let cfg = try? JSONDecoder().decode(Config.self, from: data) else { return Config() }
        return cfg
    }

    func save() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Config.directory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(self) else { return }
        try? data.write(to: Config.url, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Config.url.path)
    }

    var hasSpotifyKeys: Bool { !spotifyClientId.isEmpty && !spotifyClientSecret.isEmpty }
}

enum App {
    static var config = Config.load()
    static var delegate: AppDelegate!
}
