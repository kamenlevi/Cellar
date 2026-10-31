import Foundation

public enum BottleError: Error, Equatable {
    case invalidName(String)
    case exists(String)
    case notFound(String)
    case setupFailed(String)
    /// Wine is running in this bottle, so it can't be copied consistently.
    case inUse(String)
}

/// A bottle name that is safe to use as a folder name.
public struct BottleName: Sendable, Equatable {
    public let value: String

    public init(_ raw: String) throws(BottleError) {
        let forbidden: [Character] = ["/", ":", "\u{0}"]
        guard !raw.isEmpty, raw.count <= 64, !raw.hasPrefix("."),
              !raw.contains(where: forbidden.contains),
              raw.trimmingCharacters(in: .whitespacesAndNewlines) == raw
        else { throw .invalidName(raw) }
        value = raw
    }
}

public struct BottleInfo: Codable, Sendable, Equatable {
    public var name: String
    public var engineId: String
    public var created: Date
    public var cellarVersion: String
}

extension JSONDecoder {
    static var cellar: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

extension JSONEncoder {
    static var cellar: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

/// Bottles live in `<root>/bottles/<name>/`: `bottle.json` plus the Wine prefix in `prefix/`.
/// A folder without `bottle.json` is a half-made bottle and does not count.
public struct BottleStore: Sendable {
    public static let cellarVersion = "0.0.1"

    let paths: CellarPaths
    let engines: EngineStore
    let discard: EngineStore.Discard

    public init(paths: CellarPaths, engines: EngineStore, discard: @escaping EngineStore.Discard = EngineStore.trash) {
        self.paths = paths
        self.engines = engines
        self.discard = discard
    }

    public static var defaultsRegistryFile: URL? {
        Bundle.module.url(forResource: "cellar-defaults", withExtension: "reg")
    }

    public func create(_ name: BottleName, engineId: String?) async throws -> BottleInfo {
        let fm = FileManager.default
        let folder = paths.bottle(name.value)
        if fm.fileExists(atPath: infoFile(name).path) { throw BottleError.exists(name.value) }
        // A half-made bottle from an interrupted create is Cellar's own leftover: start again.
        if fm.fileExists(atPath: folder.path) { try fm.removeItem(at: folder) }

        let engine = try await resolveEngine(engineId)
        let prefix = folder.appending(path: "prefix", directoryHint: .isDirectory)
        try fm.createDirectory(at: prefix, withIntermediateDirectories: true)
        let runner = WineRunner(engine: engine, prefix: prefix, mode: .headless, logFile: logFile(name))

        let boot = try await runner.wine(["wineboot", "--init"])
        guard boot.exitCode == 0 else { throw BottleError.setupFailed("wineboot exited \(boot.exitCode)") }

        guard let defaults = Self.defaultsRegistryFile else { throw BottleError.setupFailed("cellar-defaults.reg missing") }
        let copied = folder.appending(path: "cellar-defaults.reg")
        try? fm.removeItem(at: copied)
        try fm.copyItem(at: defaults, to: copied)
        let reg = try await runner.wine(["regedit", "/S", copied.path])
        guard reg.exitCode == 0 else { throw BottleError.setupFailed("regedit exited \(reg.exitCode)") }
        _ = try await runner.wineserver(["-w"])

        let info = BottleInfo(name: name.value, engineId: engine.id, created: Date(), cellarVersion: Self.cellarVersion)
        try JSONEncoder.cellar.encode(info).write(to: infoFile(name), options: .atomic)
        return info
    }

    public func list() throws -> [BottleInfo] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: paths.bottles.path) else { return [] }
        return try fm.contentsOfDirectory(atPath: paths.bottles.path).sorted().compactMap { name in
            let file = paths.bottle(name).appending(path: "bottle.json")
            guard let data = fm.contents(atPath: file.path) else { return nil }
            return try? JSONDecoder.cellar.decode(BottleInfo.self, from: data)
        }
    }

    public func remove(_ name: BottleName) throws {
        _ = try info(name)
        try discard(paths.bottle(name.value))
    }

    public func runner(for name: BottleName, mode: WineMode) throws -> WineRunner {
        let info = try info(name)
        guard let engine = try engines.installedEngine(id: info.engineId) else {
            throw EngineError.notInstalled(info.engineId)
        }
        return WineRunner(engine: engine, prefix: paths.bottle(name.value).appending(path: "prefix", directoryHint: .isDirectory),
                          mode: mode, logFile: logFile(name))
    }

    /// Runs a program in the bottle. `program` is a macOS path (absolute or relative to the current
    /// folder), run from its own folder, or a Windows path such as `C:\…`, passed to Wine unchanged.
    public func run(_ name: BottleName, program: String, arguments: [String], mode: WineMode) async throws -> WineResult {
        let runner = try runner(for: name, mode: mode)
        if Self.isWindowsPath(program) || !program.contains("/") {
            return try await runner.wine([program] + arguments)
        }
        let cwd = URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
        let url = URL(filePath: program, relativeTo: cwd).standardizedFileURL
        return try await runner.wine([url.path] + arguments, cwd: url.deletingLastPathComponent())
    }

    /// Where Wine keeps its server sockets: `/tmp/.wine-<uid>`.
    public static var defaultWineServers: URL { URL(filePath: "/tmp/.wine-\(getuid())", directoryHint: .isDirectory) }

    /// The folder holding the Wine server socket of the session using `prefix`, named, as Wine names it, after the
    /// prefix folder's device and inode numbers.
    public static func wineServerFolder(for prefix: URL, in root: URL) -> URL {
        let st = (try? FileManager.default.attributesOfItem(atPath: prefix.path)) ?? [:]
        let dev = (st[.systemNumber] as? NSNumber)?.uint64Value ?? 0
        let ino = (st[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        return root.appending(path: "server-\(String(dev, radix: 16))-\(String(ino, radix: 16))", directoryHint: .isDirectory)
    }

    /// Whether a Wine session runs in the bottle (its server socket exists). Starts nothing.
    public func isRunning(_ name: BottleName, wineServers: URL = BottleStore.defaultWineServers) -> Bool {
        let prefix = paths.bottle(name.value).appending(path: "prefix", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: Self.wineServerFolder(for: prefix, in: wineServers).appending(path: "socket").path)
    }

    /// Copies a bottle as an APFS clone (`cp -c`): it costs no disk until one of the two changes, and changing one never
    /// changes the other.
    public func clone(_ source: BottleName, to target: BottleName,
                      wineServers: URL = BottleStore.defaultWineServers) throws -> BottleInfo {
        var info = try info(source)
        let fm = FileManager.default
        if fm.fileExists(atPath: paths.bottle(target.value).path) { throw BottleError.exists(target.value) }
        if isRunning(source, wineServers: wineServers) { throw BottleError.inUse(source.value) }
        let cp = Process()
        cp.executableURL = URL(filePath: "/bin/cp")
        cp.arguments = ["-c", "-R", paths.bottle(source.value).path, paths.bottle(target.value).path]
        try cp.run()
        cp.waitUntilExit()
        guard cp.terminationStatus == 0 else { throw BottleError.setupFailed("cp -c exited \(cp.terminationStatus)") }
        info.name = target.value
        try JSONEncoder.cellar.encode(info).write(to: infoFile(target), options: .atomic)
        return info
    }

    /// Points the bottle at another installed engine.
    public func setEngine(_ name: BottleName, to engineId: String) throws {
        var info = try info(name)
        guard try engines.installedEngine(id: engineId) != nil else { throw EngineError.notInstalled(engineId) }
        info.engineId = engineId
        try JSONEncoder.cellar.encode(info).write(to: infoFile(name), options: .atomic)
    }

    /// Moves the bottle to the engine that replaces its own (same Wine, with fixes), installing it if needed.
    /// Returns the new engine's id, or nil when nothing replaces it. Only call it with nothing running in the bottle.
    public func moveToNewerEngine(_ name: BottleName, manifest: EngineManifest) async throws -> String? {
        var info = try info(name)
        guard let entry = manifest.replacement(for: info.engineId) else { return nil }
        if try engines.installedEngine(id: entry.id) == nil { _ = try await engines.install(entry) }
        info.engineId = entry.id
        try JSONEncoder.cellar.encode(info).write(to: infoFile(name), options: .atomic)
        return entry.id
    }

    /// Stops this bottle's wineserver and every program in it, and nothing outside it.
    public func kill(_ name: BottleName) async throws {
        let runner = try runner(for: name, mode: .headless)
        _ = try await runner.wineserver(["-k"])
        _ = try await runner.wineserver(["-w"])
    }

    // MARK: - Helpers

    static func isWindowsPath(_ s: String) -> Bool {
        if s.contains("\\") { return true }
        let chars = Array(s)
        return chars.count >= 2 && chars[0].isLetter && chars[1] == ":"
    }

    func info(_ name: BottleName) throws -> BottleInfo {
        guard let data = FileManager.default.contents(atPath: infoFile(name).path) else {
            throw BottleError.notFound(name.value)
        }
        return try JSONDecoder.cellar.decode(BottleInfo.self, from: data)
    }

    func infoFile(_ name: BottleName) -> URL { paths.bottle(name.value).appending(path: "bottle.json") }
    func logFile(_ name: BottleName) -> URL { paths.logs.appending(path: "\(name.value).log") }

    private func resolveEngine(_ id: String?) async throws -> InstalledEngine {
        let manifest = try? EngineManifest.bundled()
        let wanted = id ?? manifest?.defaultEngine.id
        guard let wanted else { throw EngineError.notInstalled("default") }
        if let installed = try engines.installedEngine(id: wanted) { return installed }
        guard let entry = manifest?.engines.first(where: { $0.id == wanted }) else { throw EngineError.notInstalled(wanted) }
        return try await engines.install(entry)
    }
}
