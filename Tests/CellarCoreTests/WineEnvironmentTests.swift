import Foundation
import Testing
@testable import CellarCore

@Test func headlessEnvironment() throws {
    let tmp = try TempRoot()
    let engine = try FakeEngine.installed(in: tmp.url)
    let env = WineEnvironment.make(engine: engine, prefix: URL(filePath: "/tmp/b/prefix"), mode: .headless,
                                   base: ["HOME": "/Users/k", "PATH": "/usr/bin"])
    #expect(env["WINEPREFIX"] == "/tmp/b/prefix")
    #expect(env["DYLD_FALLBACK_LIBRARY_PATH"]!.hasPrefix(engine.frameworks.path))
    #expect(env["DYLD_FALLBACK_LIBRARY_PATH"]!.contains("GStreamer.framework/Versions/1.0/lib"))
    #expect(env["WINEDLLOVERRIDES"]!.contains("winemac.drv=d"))
    #expect(env["WINEDLLOVERRIDES"]!.contains("winecoreaudio.drv=d"))
    #expect(env["WINEDLLOVERRIDES"]!.contains("mscoree,mshtml="))
    #expect(env["WINEDEBUG"] == "-all")
    #expect(env["PATH"]!.hasPrefix(engine.wineBinary.deletingLastPathComponent().path))
    #expect(env["HOME"] == "/Users/k")
}

@Test func interactiveKeepsDisplayAndAudio() throws {
    let tmp = try TempRoot()
    let engine = try FakeEngine.installed(in: tmp.url)
    let env = WineEnvironment.make(engine: engine, prefix: URL(filePath: "/tmp/p"), mode: .interactive, base: [:])
    #expect(!(env["WINEDLLOVERRIDES"] ?? "").contains("winemac.drv=d"))
    #expect(!(env["WINEDLLOVERRIDES"] ?? "").contains("winecoreaudio.drv=d"))
}

@Test func runnerLogsAndReturnsExitCode() async throws {
    let tmp = try TempRoot()
    let engine = try FakeEngine.installed(in: tmp.url, wine: "#!/bin/sh\necho \"args:$*\"\necho \"pfx:$WINEPREFIX\"\nexit 3\n")
    let prefix = tmp.url.appending(path: "prefix")
    let log = tmp.url.appending(path: "logs/test.log")
    let result = try await WineRunner(engine: engine, prefix: prefix, mode: .headless, logFile: log)
        .wine(["cmd", "/c", "echo hi"])
    #expect(result.exitCode == 3)
    #expect(result.output.contains("args:cmd /c echo hi"))
    #expect(result.output.contains("pfx:\(prefix.path)"))
    let logged = try String(contentsOf: log, encoding: .utf8)
    #expect(logged.hasPrefix("=== "))
    #expect(logged.contains("args:cmd /c echo hi"))
}

@Test func argumentsWithSpacesArePassedIntact() async throws {
    let tmp = try TempRoot()
    let engine = try FakeEngine.installed(in: tmp.url, wine: "#!/bin/sh\nfor a in \"$@\"; do echo \"[$a]\"; done\n")
    let exe = #"C:\Program Files\Animal Well\Animal Well.exe"#
    let result = try await WineRunner(engine: engine, prefix: tmp.url.appending(path: "p"), mode: .headless,
                                      logFile: tmp.url.appending(path: "l.log")).wine([exe])
    #expect(result.output.split(separator: "\n").contains("[\(exe)]"))
}
