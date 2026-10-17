import Foundation

public struct D3DMetalImport: Codable, Sendable, Equatable {
    public var version: String
    public var importedAt: Date
    public var source: String
}

public enum D3DMetalError: Error, Equatable {
    case notFound(String)
    case mountFailed(String)
}

/// Apple's D3DMetal, imported from Kamen's own Game Porting Toolkit download. Cellar never
/// redistributes it; it copies `external/` and `wine/` from the toolkit's `redist/lib` folder into
/// `<root>/renderers/d3dmetal/<version>/`.
public struct D3DMetalStore: Sendable {
    let paths: CellarPaths

    public init(paths: CellarPaths) { self.paths = paths }

    /// `source` is the toolkit's `.dmg` or any folder that contains its `redist/lib`.
    public func importFrom(_ source: URL) async throws -> D3DMetalImport {
        var mounts: [URL] = []
        defer { for m in mounts.reversed() { Self.detach(m) } }

        clearLeftovers()
        var lib: URL?
        if source.pathExtension.lowercased() == "dmg" {
            let mount = try Self.attach(source)
            mounts.append(mount)
            lib = Self.findRedistLib(in: mount, depth: 6)
            // The toolkit .dmg holds a second "evaluation environment" .dmg with the files in it.
            // Only images inside Apple's own image are opened; one that won't mount is skipped.
            if lib == nil {
                for inner in Self.findDMGs(in: mount, depth: 3) {
                    guard let innerMount = try? Self.attach(inner) else { continue }
                    mounts.append(innerMount)
                    if let found = Self.findRedistLib(in: innerMount, depth: 6) { lib = found; break }
                }
            }
        } else {
            // A plain folder is only searched, never has disk images in it opened.
            lib = Self.findRedistLib(in: source, depth: 6)
        }
        guard let lib else { throw D3DMetalError.notFound(source.path) }

        let version = Self.version(of: lib) ?? "unknown"
        let fm = FileManager.default
        let destination = paths.d3dmetal.appending(path: version, directoryHint: .isDirectory)
        let staging = paths.d3dmetal.appending(path: ".staging-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: staging) }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        for part in ["external", "wine"] {
            try fm.copyItem(at: lib.appending(path: part), to: staging.appending(path: part))
        }
        let record = D3DMetalImport(version: version, importedAt: Date(), source: source.path)
        try JSONEncoder.cellar.encode(record).write(to: staging.appending(path: "IMPORT.json"))
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: staging, to: destination)
        return record
    }

    /// The most recently imported version, if any.
    public func current() throws -> D3DMetalImport? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: paths.d3dmetal.path) else { return nil }
        return try fm.contentsOfDirectory(atPath: paths.d3dmetal.path)
            .filter { !$0.hasPrefix(".") }
            .compactMap { name -> D3DMetalImport? in
                let file = paths.d3dmetal.appending(path: "\(name)/IMPORT.json")
                guard let data = fm.contents(atPath: file.path) else { return nil }
                return try? JSONDecoder.cellar.decode(D3DMetalImport.self, from: data)
            }
            .max { $0.importedAt < $1.importedAt }
    }

    private func clearLeftovers() {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: paths.d3dmetal.path)) ?? [] where name.hasPrefix(".staging-") {
            try? fm.removeItem(at: paths.d3dmetal.appending(path: name))
        }
    }

    // MARK: - Finding the files

    static func isRedistLib(_ dir: URL) -> Bool {
        let fm = FileManager.default
        return ["external/D3DMetal.framework", "external/libd3dshared.dylib", "wine/x86_64-windows/d3d12.dll"]
            .allSatisfy { fm.fileExists(atPath: dir.appending(path: $0).path) }
    }

    static func findRedistLib(in dir: URL, depth: Int) -> URL? {
        if isRedistLib(dir) { return dir }
        guard depth > 0 else { return nil }
        for child in subdirectories(of: dir) where child.pathExtension != "framework" {
            if let found = findRedistLib(in: child, depth: depth - 1) { return found }
        }
        return nil
    }

    static func findDMGs(in dir: URL, depth: Int) -> [URL] {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var found = entries.filter { $0.pathExtension.lowercased() == "dmg" }
        if depth > 0 {
            for child in subdirectories(of: dir) { found += findDMGs(in: child, depth: depth - 1) }
        }
        return found
    }

    static func subdirectories(of dir: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? []
        return entries.filter {
            let values = try? $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return values?.isDirectory == true && values?.isSymbolicLink != true
        }
    }

    static func version(of lib: URL) -> String? {
        let fm = FileManager.default
        for plist in ["external/D3DMetal.framework/Resources/Info.plist",
                      "external/D3DMetal.framework/Versions/A/Resources/Info.plist"] {
            if let data = fm.contents(atPath: lib.appending(path: plist).path),
               let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let v = dict["CFBundleShortVersionString"] as? String {
                return v
            }
        }
        return nil
    }

    // MARK: - Disk images

    /// Mounts read-only and out of sight. The terminal stays attached, so if Apple's licence
    /// agreement comes up, the person running the import reads and answers it themselves.
    static func attach(_ dmg: URL) throws -> URL {
        let mount = FileManager.default.temporaryDirectory.appending(path: "cellar-mount-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/hdiutil")
        p.arguments = ["attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mount.path, dmg.path]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: mount)
            throw D3DMetalError.mountFailed(dmg.lastPathComponent)
        }
        return mount
    }

    static func detach(_ mount: URL) {
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/hdiutil")
        p.arguments = ["detach", mount.path, "-force", "-quiet"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        try? FileManager.default.removeItem(at: mount)
    }
}
