import CryptoKit
import Foundation
@testable import CellarCore

/// A tiny stand-in engine: shell scripts named `wine` and `wineserver`, packed the way a real Cellar engine is.
enum FakeEngine {
    static let defaultWine = "#!/bin/sh\necho \"wine $@\"\n"
    static let defaultWineserver = "#!/bin/sh\necho \"wineserver $@\"\n"

    /// Lays out an engine folder named `id` inside `dir` and returns it.
    @discardableResult
    static func makeFolder(
        id: String, in dir: URL,
        wine: String = defaultWine, wineserver: String = defaultWineserver,
        includeWine: Bool = true
    ) throws -> URL {
        let fm = FileManager.default
        let root = dir.appending(path: id)
        let bin = root.appending(path: "wine/bin")
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appending(path: "Frameworks"), withIntermediateDirectories: true)
        try Data("{\"id\":\"\(id)\"}".utf8).write(to: root.appending(path: "ENGINE.json"))
        var scripts = [("wineserver", wineserver)]
        if includeWine { scripts.append(("wine", wine)) }
        for (name, body) in scripts {
            let url = bin.appending(path: name)
            try Data(body.utf8).write(to: url)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        return root
    }

    static func makeTarball(
        id: String, in dir: URL,
        wine: String = defaultWine, wineserver: String = defaultWineserver,
        includeWine: Bool = true
    ) throws -> (url: URL, sha256: String, size: Int64) {
        let staging = dir.appending(path: "fake-src-\(UUID().uuidString)")
        try makeFolder(id: id, in: staging, wine: wine, wineserver: wineserver, includeWine: includeWine)
        let tarball = dir.appending(path: "\(id).tar.xz")
        let tar = Process()
        tar.executableURL = URL(filePath: "/usr/bin/tar")
        tar.arguments = ["-C", staging.path, "-cJf", tarball.path, id]
        try tar.run()
        tar.waitUntilExit()
        try FileManager.default.removeItem(at: staging)
        let data = try Data(contentsOf: tarball)
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return (tarball, sha, Int64(data.count))
    }

    /// An installed engine built straight on disk, for tests that only need its paths.
    static func installed(id: String = "fake", in dir: URL, wine: String = defaultWine,
                          wineserver: String = defaultWineserver) throws -> InstalledEngine {
        let root = try makeFolder(id: id, in: dir, wine: wine, wineserver: wineserver)
        return InstalledEngine(root: root, id: id)
    }
}

/// A throwaway CELLAR_HOME, removed when the test ends.
final class TempRoot {
    let url: URL
    let paths: CellarPaths

    private let top: URL

    /// `rootName` puts CELLAR_HOME one level down under that name, e.g. to test paths with spaces.
    init(rootName: String? = nil) throws {
        let top = FileManager.default.temporaryDirectory.appending(path: "cellar-test-\(UUID().uuidString)")
        let url = rootName.map { top.appending(path: $0, directoryHint: .isDirectory) } ?? top
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        self.top = top
        self.url = url
        paths = CellarPaths(environment: ["CELLAR_HOME": url.path])
    }

    deinit { try? FileManager.default.removeItem(at: top) }

    /// Tests remove for real instead of filling Kamen's Trash.
    static let discard: @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
}
