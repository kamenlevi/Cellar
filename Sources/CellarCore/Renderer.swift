import Foundation

/// How a game's DirectX calls reach Metal.
public enum Renderer: String, Codable, Sendable {
    /// Apple's D3DMetal (D3D11/12), from Kamen's own Game Porting Toolkit import.
    case d3dmetal
    /// DXVK (D3D9–11) over MoltenVK, from the engine.
    case dxvk
    /// Wine's own translation over OpenGL: the fallback.
    case wined3d

    public var displayName: String {
        switch self {
        case .d3dmetal: "D3DMetal"
        case .dxvk: "DXVK"
        case .wined3d: "Wine's own"
        }
    }
}

public enum RendererError: Error, Equatable {
    case d3dmetalNotImported
    /// The game's exe is 32-bit, and D3DMetal only runs 64-bit programs.
    case d3dmetalNeeds64Bit(String)
}

public enum RendererSetup {
    /// The variables a game process needs on top of `WineEnvironment.make(…, .interactive)`.
    /// Wine looks in `WINEDLLPATH_PREPEND` for d3d11/d3d12/dxgi before its own copies.
    public static func environment(_ renderer: Renderer, engine: InstalledEngine, d3dmetal: D3DMetalImport?,
                                   paths: CellarPaths, base: [String: String]) throws -> [String: String] {
        var env = base
        func addOverrides(_ extra: String) {
            env["WINEDLLOVERRIDES"] = [env["WINEDLLOVERRIDES"], extra].compactMap { $0 }.joined(separator: ";")
        }
        switch renderer {
        case .d3dmetal:
            guard let d3dmetal else { throw RendererError.d3dmetalNotImported }
            let folder = paths.d3dmetal.appending(path: d3dmetal.version)
            let external = folder.appending(path: "external").path
            env["WINEDLLPATH_PREPEND"] = folder.appending(path: "wine").path
            env["DYLD_FALLBACK_LIBRARY_PATH"] = [external, base["DYLD_FALLBACK_LIBRARY_PATH"]].compactMap { $0 }.joined(separator: ":")
            env["DYLD_FALLBACK_FRAMEWORK_PATH"] = external
            addOverrides("d3d11,d3d12,d3d10core,dxgi=b")
        case .dxvk:
            env["WINEDLLPATH_PREPEND"] = engine.root.appending(path: "renderer/dxvk/wine").path
            addOverrides("d3d11,d3d10core,dxgi=n,b")
        case .wined3d:
            break
        }
        return env
    }
}
