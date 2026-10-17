import Foundation

/// One engine Cellar can install: where it lives on Cellar's own GitHub releases and how to verify it.
public struct EngineEntry: Codable, Equatable, Sendable {
    public var id: String
    public var wineVersion: String
    public var url: URL
    public var sha256: String
    public var size: Int64
    public var isDefault: Bool

    public init(id: String, wineVersion: String, url: URL, sha256: String, size: Int64, isDefault: Bool) {
        self.id = id
        self.wineVersion = wineVersion
        self.url = url
        self.sha256 = sha256
        self.size = size
        self.isDefault = isDefault
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

    public var defaultEngine: EngineEntry {
        guard let entry = engines.first(where: \.isDefault) else {
            preconditionFailure("engines.json has no default engine")
        }
        return entry
    }
}
