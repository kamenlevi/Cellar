import Foundation
import Testing

/// `scripts/package-engine.sh --check` must refuse an engine holding any of Apple's toolkit files.
private func check(_ folder: URL, gptkRedist: URL? = nil) throws -> (code: Int32, output: String) {
    let script = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../scripts/package-engine.sh").standardizedFileURL
    let p = Process()
    p.executableURL = URL(filePath: "/bin/bash")
    p.arguments = [script.path, "--check", folder.path]
    var env = ProcessInfo.processInfo.environment
    env["GPTK_REDIST"] = gptkRedist?.path
    p.environment = env
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    try p.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

@Test(arguments: ["libd3dshared.dylib", "atidxx64.dll", "nvngx-on-metalfx.dll", "D3DMetal.framework", "libmetalirconverter.dylib"])
func checkRefusesAppleToolkitFiles(_ name: String) throws {
    let tmp = try TempRoot()
    let engine = try FakeEngine.makeFolder(id: "e", in: tmp.url)
    let dir = engine.appending(path: "renderer/dxvk/wine/x86_64-windows")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: dir.appending(path: name))
    let result = try check(engine)
    #expect(result.code != 0)
    #expect(result.output.contains(name), "\(result.output)")
}

@Test func checkPassesACleanEngine() throws {
    let tmp = try TempRoot()
    let result = try check(try FakeEngine.makeFolder(id: "e", in: tmp.url))
    #expect(result.code == 0, "\(result.output)")
    #expect(result.output.contains("all dependencies resolve"))
}

@Test func checkRefusesACopyOfApplesDLL() throws {
    let tmp = try TempRoot()
    let redist = tmp.url.appending(path: "redist")
    let apple = redist.appending(path: "wine/x86_64-windows")
    try FileManager.default.createDirectory(at: apple, withIntermediateDirectories: true)
    try Data("apple-d3d12".utf8).write(to: apple.appending(path: "d3d12.dll"))
    let engine = try FakeEngine.makeFolder(id: "e", in: tmp.url)
    let dir = engine.appending(path: "wine/lib/wine/x86_64-windows")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data("apple-d3d12".utf8).write(to: dir.appending(path: "renamed.dll"))
    let result = try check(engine, gptkRedist: redist)
    #expect(result.code != 0)
    #expect(result.output.contains("renamed.dll"), "\(result.output)")
}
