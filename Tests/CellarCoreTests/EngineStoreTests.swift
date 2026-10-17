import Foundation
import Testing
@testable import CellarCore

private func entry(_ id: String, _ t: (url: URL, sha256: String, size: Int64)) -> EngineEntry {
    EngineEntry(id: id, wineVersion: "test", url: t.url, sha256: t.sha256, size: t.size, isDefault: true)
}

private func leftovers(_ paths: CellarPaths) throws -> [String] {
    let fm = FileManager.default
    var names: [String] = []
    for dir in [paths.engines, paths.downloads] where fm.fileExists(atPath: dir.path) {
        names += try fm.contentsOfDirectory(atPath: dir.path)
    }
    return names
}

@Test func installsAndListsEngine() async throws {
    let tmp = try TempRoot()
    let t = try FakeEngine.makeTarball(id: "fake-1", in: tmp.url)
    let store = EngineStore(paths: tmp.paths, discard: TempRoot.discard)
    let engine = try await store.install(entry("fake-1", t))
    #expect(try store.installed().map(\.id) == ["fake-1"])
    #expect(FileManager.default.isExecutableFile(atPath: engine.wineBinary.path))
    #expect(engine.frameworks.lastPathComponent == "Frameworks")
}

@Test func checksumMismatchInstallsNothing() async throws {
    let tmp = try TempRoot()
    var e = entry("fake-1", try FakeEngine.makeTarball(id: "fake-1", in: tmp.url))
    e.sha256 = String(repeating: "0", count: 64)
    let store = EngineStore(paths: tmp.paths, discard: TempRoot.discard)
    do {
        _ = try await store.install(e)
        Issue.record("install should have failed")
    } catch let EngineError.checksumMismatch(expected, _) {
        #expect(expected == e.sha256)
    }
    #expect(try store.installed().isEmpty)
    #expect(try leftovers(tmp.paths).isEmpty)
}

@Test func truncatedDownloadInstallsNothing() async throws {
    let tmp = try TempRoot()
    let t = try FakeEngine.makeTarball(id: "fake-1", in: tmp.url)
    let data = try Data(contentsOf: t.url)
    try data.prefix(data.count / 2).write(to: t.url)
    let store = EngineStore(paths: tmp.paths, discard: TempRoot.discard)
    await #expect(throws: EngineError.self) { try await store.install(entry("fake-1", t)) }
    #expect(try store.installed().isEmpty)
    #expect(try leftovers(tmp.paths).isEmpty)
}

@Test func missingWineBinaryIsBadLayout() async throws {
    let tmp = try TempRoot()
    let t = try FakeEngine.makeTarball(id: "fake-1", in: tmp.url, includeWine: false)
    let store = EngineStore(paths: tmp.paths, discard: TempRoot.discard)
    do {
        _ = try await store.install(entry("fake-1", t))
        Issue.record("install should have failed")
    } catch EngineError.badLayout {
    }
    #expect(try store.installed().isEmpty)
    #expect(try leftovers(tmp.paths).isEmpty)
}

@Test func reinstallOverExistingIsNoOp() async throws {
    let tmp = try TempRoot()
    let t = try FakeEngine.makeTarball(id: "fake-1", in: tmp.url)
    let store = EngineStore(paths: tmp.paths, discard: TempRoot.discard)
    let first = try await store.install(entry("fake-1", t))
    try FileManager.default.removeItem(at: t.url)
    let second = try await store.install(entry("fake-1", t))
    #expect(second.root == first.root)
}

@Test func removeMovesToTrash() async throws {
    let tmp = try TempRoot()
    let t = try FakeEngine.makeTarball(id: "fake-1", in: tmp.url)
    let store = EngineStore(paths: tmp.paths, discard: TempRoot.discard)
    _ = try await store.install(entry("fake-1", t))
    try store.remove(id: "fake-1")
    #expect(try store.installed().isEmpty)
    #expect(throws: EngineError.notInstalled("fake-1")) { try store.remove(id: "fake-1") }
}

// Final review fixes

@Test func leftoversFromInterruptedInstallAreCleared() async throws {
    let tmp = try TempRoot()
    let fm = FileManager.default
    let staleStaging = tmp.paths.engines.appending(path: ".staging-old")
    try fm.createDirectory(at: staleStaging.appending(path: "big"), withIntermediateDirectories: true)
    try fm.createDirectory(at: tmp.paths.downloads, withIntermediateDirectories: true)
    try Data("half".utf8).write(to: tmp.paths.downloads.appending(path: "other.part"))
    let t = try FakeEngine.makeTarball(id: "fake-1", in: tmp.url)
    _ = try await EngineStore(paths: tmp.paths, discard: TempRoot.discard).install(entry("fake-1", t))
    #expect(!fm.fileExists(atPath: staleStaging.path))
    #expect(try leftovers(tmp.paths) == ["fake-1"])
}

@Test(arguments: ["../x", "a/b", "..", ".hidden", "", "../../Applications/Foo.app/Contents/SharedSupport"])
func engineIdsCannotEscapeTheEnginesFolder(_ id: String) async throws {
    let tmp = try TempRoot()
    let store = EngineStore(paths: tmp.paths, discard: TempRoot.discard)
    #expect(throws: EngineError.invalidId(id)) { try store.remove(id: id) }
    #expect(throws: EngineError.invalidId(id)) { _ = try store.installedEngine(id: id) }
}
