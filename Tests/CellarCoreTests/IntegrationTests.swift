import Foundation
import Testing
@testable import CellarCore

/// Real engine, real Wine, fully headless (no window, no sound). Opt in with CELLAR_INTEGRATION=1.
/// CELLAR_ENGINE_TARBALL=/path/to.tar.xz installs from a local copy instead of the GitHub release.
@Test(.enabled(if: ProcessInfo.processInfo.environment["CELLAR_INTEGRATION"] == "1"), .timeLimit(.minutes(20)))
func realEngineInstallsAndRunsCmd() async throws {
    // A root with a space and an accent, like ~/Library/Application Support/Cellar has a space.
    let tmp = try TempRoot(rootName: "Cellar Tést")
    var entry = try EngineManifest.bundled().defaultEngine
    if let local = ProcessInfo.processInfo.environment["CELLAR_ENGINE_TARBALL"] {
        entry.url = URL(filePath: local)
    }
    let engines = EngineStore(paths: tmp.paths, discard: TempRoot.discard)
    _ = try await engines.install(entry)

    let bottles = BottleStore(paths: tmp.paths, engines: engines, discard: TempRoot.discard)
    let name = try BottleName("Cellar Test")
    _ = try await bottles.create(name, engineId: nil)

    let result = try await bottles.run(name, program: "cmd", arguments: ["/c", "echo", "cellar-ok"], mode: .headless)
    #expect(result.exitCode == 0, "\(result.output)")
    #expect(result.output.contains("cellar-ok"), "\(result.output)")

    let userReg = try String(contentsOf: tmp.paths.bottle("Cellar Test").appending(path: "prefix/user.reg"), encoding: .utf8)
    #expect(userReg.contains(#""RetinaMode"="y""#))

    // A real .exe under a folder shaped like a Mac app bundle, run by its macOS path.
    let folder = tmp.url.appending(path: "Games/Animal Well.app/Contents")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let exe = folder.appending(path: "cmd copy.exe")
    try FileManager.default.copyItem(
        at: tmp.paths.bottle("Cellar Test").appending(path: "prefix/drive_c/windows/system32/cmd.exe"), to: exe)
    let fromMacPath = try await bottles.run(name, program: exe.path, arguments: ["/c", "echo", "from-mac-path"], mode: .headless)
    #expect(fromMacPath.exitCode == 0, "\(fromMacPath.output)")
    #expect(fromMacPath.output.contains("from-mac-path"), "\(fromMacPath.output)")

    try await bottles.kill(name)
    try bottles.remove(name)
}

/// Real Valve installer, real engine, headless (the Steam window itself needs a display, so it isn't started).
/// Opt in with CELLAR_INTEGRATION=1 CELLAR_STEAM=1.
@Test(.enabled(if: ProcessInfo.processInfo.environment["CELLAR_INTEGRATION"] == "1"
               && ProcessInfo.processInfo.environment["CELLAR_STEAM"] == "1"),
      .timeLimit(.minutes(20)))
func realSteamInstallsHeadless() async throws {
    let tmp = try TempRoot(rootName: "Cellar Steam Tést")
    var entry = try EngineManifest.bundled().defaultEngine
    if let local = ProcessInfo.processInfo.environment["CELLAR_ENGINE_TARBALL"] {
        entry.url = URL(filePath: local)
    }
    let engines = EngineStore(paths: tmp.paths, discard: TempRoot.discard)
    _ = try await engines.install(entry)
    let bottles = BottleStore(paths: tmp.paths, engines: engines, discard: TempRoot.discard)
    let steam = SteamStore(paths: tmp.paths, bottles: bottles, engines: engines, macSteam: { false })

    try await steam.install()
    #expect(steam.isInstalled())
    let running = try await steam.processes()
    #expect(!running.contains("steam.exe"), "\(running)")
    let status = try await steam.status()
    #expect(status.installed && !status.running)
    try await steam.stop()
}
