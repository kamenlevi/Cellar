import Foundation

public enum LaunchMode: String, Codable, Sendable {
    /// Start the game's exe directly beside the running Steam (each game gets its own renderer).
    case direct
    /// Ask Steam to start it (steam.exe -applaunch), for games that refuse a direct start.
    case throughSteam
}

/// What Cellar knows about one game. Lives in games.json, not in code.
public struct GameProfile: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var appid: Int
    /// Path of the exe inside the game's install folder.
    public var exe: String
    public var renderer: Renderer
    /// Save folder under the Windows user profile, e.g. "AppData/LocalLow/Mobius Digital/Outer Wilds".
    public var saves: String?
    public var launch: LaunchMode

    public init(id: String, name: String, appid: Int, exe: String, renderer: Renderer, saves: String? = nil, launch: LaunchMode = .direct) {
        self.id = id; self.name = name; self.appid = appid; self.exe = exe
        self.renderer = renderer; self.saves = saves; self.launch = launch
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        appid = try c.decode(Int.self, forKey: .appid)
        exe = try c.decode(String.self, forKey: .exe)
        renderer = try c.decode(Renderer.self, forKey: .renderer)
        saves = try c.decodeIfPresent(String.self, forKey: .saves)
        launch = try c.decodeIfPresent(LaunchMode.self, forKey: .launch) ?? .direct
    }
}

public enum GameProfiles {
    public static func bundled() throws -> [GameProfile] {
        guard let url = Bundle.module.url(forResource: "games", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        return try JSONDecoder().decode([GameProfile].self, from: Data(contentsOf: url))
    }

    /// By id ("outer-wilds"), Steam appid ("753640") or name, ignoring case.
    public static func find(_ query: String, in profiles: [GameProfile]) -> GameProfile? {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return profiles.first { $0.id == q || String($0.appid) == q || $0.name.lowercased() == q }
    }
}
