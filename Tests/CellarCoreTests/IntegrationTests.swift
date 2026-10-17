import Foundation
import Testing
@testable import CellarCore

/// Real engine, real Wine, fully headless (no window, no sound). Opt in with CELLAR_INTEGRATION=1.
/// CELLAR_ENGINE_TARBALL=/path/to.tar.xz installs from a local copy instead of the GitHub release.
@Test(.enabled(if: ProcessInfo.processInfo.environment["CELLAR_INTEGRATION"] == "1"), .timeLimit(.minutes(20)))
func realEngineInstallsAndRunsCmd() async throws {
    let tmp = try TempRoot()
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

    try await bottles.kill(name)
    try bottles.remove(name)
}
