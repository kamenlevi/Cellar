import Foundation
import Testing
@testable import CellarCore

private func setup() throws -> (TempRoot, InstalledEngine, [String: String]) {
    let tmp = try TempRoot(rootName: "Cellar Tést")
    let engine = try FakeEngine.installed(in: tmp.paths.engines)
    let base = WineEnvironment.make(engine: engine, prefix: URL(filePath: "/tmp/p"), mode: .interactive, base: ["HOME": "/Users/k"])
    return (tmp, engine, base)
}

private let imported = D3DMetalImport(version: "3.0", importedAt: Date(), source: "/x.dmg")

@Test func d3dmetalEnvironmentPointsAtTheImportedCopy() throws {
    let (tmp, engine, base) = try setup()
    let env = try RendererSetup.environment(.d3dmetal, engine: engine, d3dmetal: imported, paths: tmp.paths, base: base)
    let d3d = tmp.paths.d3dmetal.appending(path: "3.0").path
    #expect(env["WINEDLLPATH_PREPEND"] == d3d + "/wine")
    #expect(env["DYLD_FALLBACK_LIBRARY_PATH"]!.hasPrefix(d3d + "/external:"))
    #expect(env["DYLD_FALLBACK_LIBRARY_PATH"]!.hasSuffix(base["DYLD_FALLBACK_LIBRARY_PATH"]!))
    #expect(env["DYLD_FALLBACK_FRAMEWORK_PATH"] == d3d + "/external")
    #expect(env["WINEDLLOVERRIDES"]!.contains("winemenubuilder.exe=d"))
    #expect(env["WINEDLLOVERRIDES"]!.contains("d3d11,d3d12,d3d10core,dxgi=b"))
}

@Test func d3dmetalWithoutImportThrows() throws {
    let (tmp, engine, base) = try setup()
    #expect(throws: RendererError.d3dmetalNotImported) {
        _ = try RendererSetup.environment(.d3dmetal, engine: engine, d3dmetal: nil, paths: tmp.paths, base: base)
    }
    #expect(RendererError.d3dmetalNotImported.errorDescription == "This game needs Apple's D3DMetal, which isn't imported yet.")
    #expect(RendererError.d3dmetalNotImported.recoverySuggestion
            == "Run: cellar d3dmetal import ~/Downloads/<Evaluation environment for Windows games>.dmg")
}

@Test func dxvkEnvironmentUsesTheEngineCopy() throws {
    let (tmp, engine, base) = try setup()
    let env = try RendererSetup.environment(.dxvk, engine: engine, d3dmetal: nil, paths: tmp.paths, base: base)
    #expect(env["WINEDLLPATH_PREPEND"] == engine.root.appending(path: "renderer/dxvk/wine").path)
    #expect(env["WINEDLLOVERRIDES"]!.contains("d3d11,d3d10core,dxgi=n,b"))
    #expect(env["WINEDLLOVERRIDES"]!.contains("mscoree,mshtml="))
}

@Test func wined3dAddsNothing() throws {
    let (tmp, engine, base) = try setup()
    let env = try RendererSetup.environment(.wined3d, engine: engine, d3dmetal: nil, paths: tmp.paths, base: base)
    #expect(env == base)
}
