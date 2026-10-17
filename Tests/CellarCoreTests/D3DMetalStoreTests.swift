import Foundation
import Testing
@testable import CellarCore

/// Lays out what the Game Porting Toolkit's `redist/lib` folder looks like, under `base/a/b/`.
private func fakeGPTk(in base: URL, version: String = "3.0") throws {
    let lib = base.appending(path: "a/b/redist/lib")
    let resources = lib.appending(path: "external/D3DMetal.framework/Resources")
    let windows = lib.appending(path: "wine/x86_64-windows")
    for dir in [resources, windows] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
    let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": version], format: .xml, options: 0)
    try plist.write(to: resources.appending(path: "Info.plist"))
    try Data("dylib".utf8).write(to: lib.appending(path: "external/libd3dshared.dylib"))
    try Data("dll".utf8).write(to: windows.appending(path: "d3d12.dll"))
}

@Test func importsFromFolderLayout() async throws {
    let tmp = try TempRoot()
    let source = tmp.url.appending(path: "gptk")
    try fakeGPTk(in: source)
    let store = D3DMetalStore(paths: tmp.paths)
    let imported = try await store.importFrom(source)
    #expect(imported.version == "3.0")
    #expect(FileManager.default.fileExists(atPath:
        tmp.paths.d3dmetal.appending(path: "3.0/wine/x86_64-windows/d3d12.dll").path))
    #expect(FileManager.default.fileExists(atPath:
        tmp.paths.d3dmetal.appending(path: "3.0/external/libd3dshared.dylib").path))
    #expect(try store.current()?.version == "3.0")
}

@Test func folderWithoutD3DMetalThrowsNotFound() async throws {
    let tmp = try TempRoot()
    let empty = tmp.url.appending(path: "nothing-here")
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    await #expect(throws: D3DMetalError.self) { try await D3DMetalStore(paths: tmp.paths).importFrom(empty) }
    #expect(try D3DMetalStore(paths: tmp.paths).current() == nil)
}

@Test func doctorReportsMissingRosettaWithFix() throws {
    let tmp = try TempRoot()
    let checks = try Doctor(paths: tmp.paths, rosettaProbe: { false }).run()
    #expect(checks.first?.name == "Rosetta 2")
    #expect(checks.first?.ok == false)
    #expect(checks.first?.fix == "Run: softwareupdate --install-rosetta --agree-to-license")
}

@Test func requireRosettaThrowsWhenMissing() throws {
    let tmp = try TempRoot()
    #expect(throws: (any Error).self) { try Doctor(paths: tmp.paths, rosettaProbe: { false }).requireRosetta() }
    try Doctor(paths: tmp.paths, rosettaProbe: { true }).requireRosetta()
}

@Test func d3dmetalMissingGivesAppleInstructions() throws {
    let tmp = try TempRoot()
    let checks = try Doctor(paths: tmp.paths, rosettaProbe: { true }).run()
    let d3d = try #require(checks.first { $0.name == "D3DMetal" })
    #expect(d3d.ok == false)
    #expect(d3d.optional)
    #expect(d3d.fix?.contains("developer.apple.com/games/game-porting-toolkit") == true)
    #expect(d3d.fix?.contains("cellar d3dmetal import") == true)
}

@Test func doctorNamesChecksInOrder() throws {
    let tmp = try TempRoot()
    let checks = try Doctor(paths: tmp.paths, rosettaProbe: { true }, freeBytes: { 100_000_000_000 }).run()
    #expect(checks.map(\.name) == ["Rosetta 2", "Engine", "D3DMetal", "Free disk space ≥ 5 GB"])
    #expect(checks.first { $0.name == "Engine" }?.fix == "Run: cellar engine install")
}

@Test func lowDiskSpaceFails() throws {
    let tmp = try TempRoot()
    let checks = try Doctor(paths: tmp.paths, rosettaProbe: { true }, freeBytes: { 1_000_000_000 }).run()
    let disk = try #require(checks.last)
    #expect(disk.ok == false)
    #expect(disk.fix == "Free up space on the startup disk")
}
