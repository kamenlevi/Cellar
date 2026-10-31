import Foundation

/// One engine Cellar can install: where it lives on Cellar's own GitHub releases and how to verify it.
public struct EngineEntry: Codable, Equatable, Sendable {
    public var id: String
    public var wineVersion: String
    public var url: URL
    public var sha256: String
    public var size: Int64
    public var isDefault: Bool
    /// Engines this one stands in for: the same Wine with fixes, so a bottle made with one of them moves here.
    public var replaces: [String]

    public init(id: String, wineVersion: String, url: URL, sha256: String, size: Int64, isDefault: Bool,
                replaces: [String] = []) {
        self.id = id
        self.wineVersion = wineVersion
        self.url = url
        self.sha256 = sha256
        self.size = size
        self.isDefault = isDefault
        self.replaces = replaces
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id), wineVersion: try c.decode(String.self, forKey: .wineVersion),
                  url: try c.decode(URL.self, forKey: .url), sha256: try c.decode(String.self, forKey: .sha256),
                  size: try c.decode(Int64.self, forKey: .size), isDefault: try c.decode(Bool.self, forKey: .isDefault),
                  replaces: try c.decodeIfPresent([String].self, forKey: .replaces) ?? [])
    }
}

/// The engines Cellar knows about, shipped inside the app as `engines.json`.
public struct EngineManifest: Codable, Sendable {
    public var engines: [EngineEntry]

    public static func bundled() throws -> EngineManifest {
        guard let url = Bundle.module.url(forResource: "engines", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(EngineManifest.self, from: Data(contentsOf: url))
    }

    /// The engine a bottle made with `id` should move to, if one replaces it.
    public func replacement(for id: String) -> EngineEntry? {
        engines.first { $0.replaces.contains(id) }
    }

    public var defaultEngine: EngineEntry {
        guard let entry = engines.first(where: \.isDefault) else {
            preconditionFailure("engines.json has no default engine")
        }
        return entry
    }
}
