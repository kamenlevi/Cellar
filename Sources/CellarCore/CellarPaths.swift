import Foundation

/// Where Cellar keeps everything. One root, so a test or a "fresh user" run can use a throwaway one.
public struct CellarPaths: Sendable {
    public let root: URL
    public let logs: URL

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        if let custom = environment["CELLAR_HOME"], !custom.isEmpty {
            root = URL(filePath: custom, directoryHint: .isDirectory)
            logs = root.appending(path: "logs", directoryHint: .isDirectory)
        } else {
            root = home.appending(path: "Library/Application Support/Cellar", directoryHint: .isDirectory)
            logs = home.appending(path: "Library/Logs/Cellar", directoryHint: .isDirectory)
        }
    }

    public var engines: URL { root.appending(path: "engines", directoryHint: .isDirectory) }
    public var bottles: URL { root.appending(path: "bottles", directoryHint: .isDirectory) }
    public var d3dmetal: URL { root.appending(path: "renderers/d3dmetal", directoryHint: .isDirectory) }
    public var downloads: URL { root.appending(path: "downloads", directoryHint: .isDirectory) }

    public func engine(_ id: String) -> URL { engines.appending(path: id, directoryHint: .isDirectory) }
    public func bottle(_ name: String) -> URL { bottles.appending(path: name, directoryHint: .isDirectory) }
}
