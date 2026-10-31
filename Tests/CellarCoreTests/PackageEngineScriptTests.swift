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

@Test func checkRefusesAMacDriverWithoutTheFocusFix() throws {
    let tmp = try TempRoot()
    let engine = try FakeEngine.makeFolder(id: "sikarugir-10.0_6-c2", in: tmp.url)
    let dir = engine.appending(path: "wine/lib/wine/x86_64-unix")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data("not the fixed build".utf8).write(to: dir.appending(path: "winemac.so"))
    let result = try check(engine)
    #expect(result.code != 0)
    #expect(result.output.contains("focus-fixed"), "\(result.output)")
}

/// A source-built engine's ntdll.so, carrying the given marker strings.
private func sourceBuiltEngine(_ tmp: TempRoot, ntdll markers: [String], monoAndGecko: Bool = true) throws -> URL {
    let engine = try FakeEngine.makeFolder(id: "crossover-25.1.1-c1", in: tmp.url)
    try Data(#"{"id":"crossover-25.1.1-c1"}"#.utf8).write(to: engine.appending(path: "ENGINE.json"))
    let unix = engine.appending(path: "wine/lib/wine/x86_64-unix")
    try FileManager.default.createDirectory(at: unix, withIntermediateDirectories: true)
    try Data(("\u{0}" + markers.joined(separator: "\u{0}") + "\u{0}").utf8).write(to: unix.appending(path: "ntdll.so"))
    if monoAndGecko {
        for addon in ["mono", "gecko"] {
            try FileManager.default.createDirectory(at: engine.appending(path: "wine/share/wine/\(addon)"), withIntermediateDirectories: true)
        }
    }
    return engine
}

@Test func checkRefusesAnEngineWithoutTheD3DMetalBridge() throws {
    let tmp = try TempRoot()
    let result = try check(try sourceBuiltEngine(tmp, ntdll: ["WINEDLLPATH_PREPEND"]))
    #expect(result.code != 0)
    #expect(result.output.contains("D3DMetal bridge"), "\(result.output)")
}

@Test func checkRefusesAnEngineThatIgnoresWinedllpathPrepend() throws {
    let tmp = try TempRoot()
    let result = try check(try sourceBuiltEngine(tmp, ntdll: ["CX_APPLEGPTK_LIBD3DSHARED_PATH"]))
    #expect(result.code != 0)
    #expect(result.output.contains("WINEDLLPATH_PREPEND"), "\(result.output)")
}

@Test func checkRefusesASourceBuiltEngineWithoutMonoOrGecko() throws {
    let tmp = try TempRoot()
    let result = try check(try sourceBuiltEngine(tmp, ntdll: ["CX_APPLEGPTK_LIBD3DSHARED_PATH", "WINEDLLPATH_PREPEND"],
                                                 monoAndGecko: false))
    #expect(result.code != 0)
    #expect(result.output.contains("Mono"), "\(result.output)")
}

@Test func checkPassesAnEngineWithBridgeAndPrepend() throws {
    let tmp = try TempRoot()
    let result = try check(try sourceBuiltEngine(tmp, ntdll: ["CX_APPLEGPTK_LIBD3DSHARED_PATH", "WINEDLLPATH_PREPEND"]))
    #expect(result.code == 0, "\(result.output)")
}

@Test func checkAllowsHomebrewTextInsideAWindowsDLL() throws {
    // A Windows DLL can't load a Mac library; a Homebrew path in one is only text (a mingw header's file name).
    let tmp = try TempRoot()
    let engine = try sourceBuiltEngine(tmp, ntdll: ["CX_APPLEGPTK_LIBD3DSHARED_PATH", "WINEDLLPATH_PREPEND"])
    let windows = engine.appending(path: "wine/lib/wine/x86_64-windows")
    try FileManager.default.createDirectory(at: windows, withIntermediateDirectories: true)
    try Data("MZ\u{0}/usr/local/Cellar/mingw-w64/13.0.0/include/assert.h\u{0}".utf8).write(to: windows.appending(path: "xaudio2_9.dll"))
    let result = try check(engine)
    #expect(result.code == 0, "\(result.output)")
    #expect(result.output.contains("/usr/local/Cellar/mingw-w64/13.0.0/include/assert.h"), "the text is still shown: \(result.output)")
}

@Test func checkRefusesALibraryThatPointsIntoHomebrew() throws {
    // A source build links against Homebrew on the build machine; a path left behind breaks on Kamen's Mac.
    let tmp = try TempRoot()
    let engine = try sourceBuiltEngine(tmp, ntdll: ["CX_APPLEGPTK_LIBD3DSHARED_PATH", "WINEDLLPATH_PREPEND"])
    let lib = engine.appending(path: "wine/lib/wine/x86_64-unix/winemac.so")
    try Data("\u{0}/usr/local/opt/freetype/lib/libfreetype.6.dylib\u{0}".utf8).write(to: lib)
    let result = try check(engine)
    #expect(result.code != 0)
    #expect(result.output.contains("Homebrew"), "\(result.output)")
}
