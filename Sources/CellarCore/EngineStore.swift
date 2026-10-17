import CryptoKit
import Foundation

/// An engine unpacked under `<root>/engines/<id>`.
public struct InstalledEngine: Equatable, Sendable {
    public let id: String
    public let root: URL

    public init(root: URL, id: String) {
        self.root = root
        self.id = id
    }

    public var wineBinary: URL { root.appending(path: "wine/bin/wine") }
    public var wineserverBinary: URL { root.appending(path: "wine/bin/wineserver") }
    public var frameworks: URL { root.appending(path: "Frameworks", directoryHint: .isDirectory) }
}

public enum EngineError: Error, Equatable {
    case checksumMismatch(expected: String, actual: String)
    case badLayout(String)
    case notInstalled(String)
}

/// Downloads, verifies and unpacks engines. An install either completes or leaves nothing behind.
public struct EngineStore: Sendable {
    public typealias Discard = @Sendable (URL) throws -> Void

    let paths: CellarPaths
    let session: URLSession
    let discard: Discard

    public static let trash: Discard = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }

    public init(paths: CellarPaths, session: URLSession = .shared, discard: @escaping Discard = EngineStore.trash) {
        self.paths = paths
        self.session = session
        self.discard = discard
    }

    public func install(
        _ entry: EngineEntry,
        progress: @Sendable (Int64, Int64) -> Void = { _, _ in }
    ) async throws -> InstalledEngine {
        if let existing = try installedEngine(id: entry.id) { return existing }

        let fm = FileManager.default
        try fm.createDirectory(at: paths.downloads, withIntermediateDirectories: true)
        try fm.createDirectory(at: paths.engines, withIntermediateDirectories: true)
        let part = paths.downloads.appending(path: "\(entry.id).part")
        let staging = paths.engines.appending(path: ".staging-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? fm.removeItem(at: part)
            try? fm.removeItem(at: staging)
        }

        try await download(entry.url, to: part)
        progress(entry.size, entry.size)

        let actual = try Self.sha256(of: part)
        guard actual == entry.sha256.lowercased() else {
            throw EngineError.checksumMismatch(expected: entry.sha256, actual: actual)
        }

        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        try Self.untar(part, into: staging)
        let unpacked = InstalledEngine(root: staging.appending(path: entry.id, directoryHint: .isDirectory), id: entry.id)
        for binary in [unpacked.wineBinary, unpacked.wineserverBinary] where !fm.isExecutableFile(atPath: binary.path) {
            throw EngineError.badLayout("missing \(binary.lastPathComponent) in \(entry.id)")
        }

        let destination = paths.engine(entry.id)
        try fm.moveItem(at: unpacked.root, to: destination)
        return InstalledEngine(root: destination, id: entry.id)
    }

    public func installed() throws -> [InstalledEngine] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: paths.engines.path) else { return [] }
        return try fm.contentsOfDirectory(atPath: paths.engines.path)
            .filter { !$0.hasPrefix(".") }
            .sorted()
            .compactMap { try installedEngine(id: $0) }
    }

    public func installedEngine(id: String) throws -> InstalledEngine? {
        let engine = InstalledEngine(root: paths.engine(id), id: id)
        return FileManager.default.isExecutableFile(atPath: engine.wineBinary.path) ? engine : nil
    }

    public func remove(id: String) throws {
        guard try installedEngine(id: id) != nil else { throw EngineError.notInstalled(id) }
        try discard(paths.engine(id))
    }

    // MARK: - Steps

    private func download(_ url: URL, to part: URL) async throws {
        let fm = FileManager.default
        try? fm.removeItem(at: part)
        if url.isFileURL {
            try fm.copyItem(at: url, to: part)
            return
        }
        let (temporary, response) = try await session.download(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? fm.removeItem(at: temporary)
            throw URLError(.badServerResponse)
        }
        try fm.moveItem(at: temporary, to: part)
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func untar(_ archive: URL, into directory: URL) throws {
        let tar = Process()
        tar.executableURL = URL(filePath: "/usr/bin/tar")
        tar.arguments = ["-xJf", archive.path, "-C", directory.path]
        tar.standardError = FileHandle.nullDevice
        try tar.run()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0 else {
            throw EngineError.badLayout("could not unpack \(archive.lastPathComponent)")
        }
    }
}
