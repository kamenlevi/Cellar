import Foundation

public enum SteamError: Error, Equatable {
    case notInstalled
    case badInstaller(String)
    case installFailed(String)
}

public struct SteamStatus: Equatable, Sendable {
    public var installed: Bool
    public var running: Bool
    public var webhelperRunning: Bool
    public var macSteamRunning: Bool
    public var health: SteamHealth

    public init(installed: Bool, running: Bool, webhelperRunning: Bool, macSteamRunning: Bool, health: SteamHealth) {
        self.installed = installed
        self.running = running
        self.webhelperRunning = webhelperRunning
        self.macSteamRunning = macSteamRunning
        self.health = health
    }

    /// What `cellar steam status` prints. Never contains an account id.
    public func lines() -> [String] {
        func when(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .shortened) }
        let signIn: String = switch health.signIn {
        case .signedIn(let since): "yes (since \(when(since)))"
        case .signedOut: "no"
        case .unknown: "unknown"
        }
        let loop = health.crashLoop
            ? "YES — \(health.webhelperLaunchesLast10Min) web-helper starts in 10 minutes (the August failure). Try: cellar steam restart"
            : "no"
        return [
            "Installed: \(installed ? "yes" : "no")",
            "Running: \(running ? "yes" : "no")",
            "Signed in: \(signIn)",
            "Web helper: \(webhelperRunning ? "running" : "not running")",
            "Crash loop: \(loop)",
            "Last update check: \(health.lastUpdateCheck.map(when) ?? "never")",
            "Steam for Mac: \(macSteamRunning ? "running" : "not running")",
        ]
    }
}

public enum StartOutcome: Equatable, Sendable {
    case started
    case broughtForward
    case clearedStaleStateThenStarted
}

/// Windows Steam in Cellar's one shared bottle, "Steam". Kamen signs in himself; Cellar never touches credentials.
public struct SteamStore: Sendable {
    public static let bottleName = "Steam"
    public static let installerURL = URL(string: "https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe")!
    /// CEF's sandbox doesn't work under Wine. Never "-silent": Steam must stay reachable.
    public static let launchFlags = ["-no-cef-sandbox"]
    /// Wine starts these for any program (tasklist included); on their own they don't mean Steam is stuck.
    static let wineSystemProcesses: Set<String> = [
        "tasklist.exe", "conhost.exe", "services.exe", "winedevice.exe", "plugplay.exe",
        "svchost.exe", "rpcss.exe", "explorer.exe", "start.exe", "cmd.exe",
    ]

    let paths: CellarPaths
    let bottles: BottleStore
    let engines: EngineStore
    let installer: URL
    let engineId: String?
    let macSteam: @Sendable () -> Bool

    public init(paths: CellarPaths, bottles: BottleStore, engines: EngineStore,
                installer: URL = SteamStore.installerURL, engineId: String? = nil,
                macSteam: @escaping @Sendable () -> Bool = MacSteam.isRunning) {
        self.paths = paths
        self.bottles = bottles
        self.engines = engines
        self.installer = installer
        self.engineId = engineId
        self.macSteam = macSteam
    }

    var name: BottleName { try! BottleName(Self.bottleName) }

    public var steamFolder: URL {
        paths.bottle(Self.bottleName).appending(path: "prefix/drive_c/Program Files (x86)/Steam", directoryHint: .isDirectory)
    }

    /// Valve ships "steam.exe"; some setups show "Steam.exe".
    public var steamExe: URL {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: steamFolder.path)) ?? []
        let actual = names.first { $0.lowercased() == "steam.exe" } ?? "steam.exe"
        return steamFolder.appending(path: actual)
    }

    public func isInstalled() -> Bool { FileManager.default.fileExists(atPath: steamExe.path) }

    // MARK: - Install

    public func install() async throws {
        if isInstalled() { return }
        if try !bottles.list().contains(where: { $0.name == Self.bottleName }) {
            _ = try await bottles.create(name, engineId: engineId)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: paths.downloads, withIntermediateDirectories: true)
        let part = paths.downloads.appending(path: "SteamSetup.exe.part")
        let setup = paths.downloads.appending(path: "SteamSetup.exe")
        defer {
            try? fm.removeItem(at: part)
            try? fm.removeItem(at: setup)
        }
        try await downloadInstaller(to: part)
        try Self.checkInstaller(part)
        try? fm.removeItem(at: setup)
        try fm.moveItem(at: part, to: setup)

        let result = try await bottles.run(name, program: setup.path, arguments: ["/S"], mode: .headless)
        _ = try await bottles.runner(for: name, mode: .headless).wineserver(["-w"])
        guard isInstalled() else { throw SteamError.installFailed("installer exited \(result.exitCode)") }
    }

    private func downloadInstaller(to part: URL) async throws {
        let fm = FileManager.default
        try? fm.removeItem(at: part)
        if installer.isFileURL {
            try fm.copyItem(at: installer, to: part)
            return
        }
        let (temporary, response) = try await URLSession.shared.download(from: installer)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            try? fm.removeItem(at: temporary)
            throw SteamError.badInstaller("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        try fm.moveItem(at: temporary, to: part)
    }

    /// A Windows program (starts with "MZ") of a plausible size; anything else is never run.
    static func checkInstaller(_ file: URL) throws {
        let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
        guard (1_000_000...20_000_000).contains(size) else { throw SteamError.badInstaller("unexpected size \(size) bytes") }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        guard try handle.read(upToCount: 2) == Data("MZ".utf8) else { throw SteamError.badInstaller("not a Windows program") }
    }

    // MARK: - Run

    public func processes() async throws -> [String] {
        let result = try await bottles.runner(for: name, mode: .headless).wine(["tasklist", "/fo", "csv", "/nh"])
        return result.output.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("\""), let close = line.dropFirst().firstIndex(of: "\"") else { return nil }
            return line[line.index(after: line.startIndex)..<close].lowercased()
        }
    }

    public func start() async throws -> StartOutcome {
        guard isInstalled() else { throw SteamError.notInstalled }
        let running = try await processes()
        let outcome: StartOutcome
        if running.contains("steam.exe") {
            // Steam hands this to the instance that's already running, which shows its window.
            outcome = .broughtForward
        } else if running.contains(where: { !Self.wineSystemProcesses.contains($0) }) {
            try await bottles.kill(name)
            outcome = .clearedStaleStateThenStarted
        } else {
            outcome = .started
        }
        try bottles.runner(for: name, mode: .interactive).spawn([steamExe.path] + Self.launchFlags, cwd: steamFolder)
        return outcome
    }

    public func stop() async throws {
        guard isInstalled() else { throw SteamError.notInstalled }
        if try await processes().contains("steam.exe") {
            _ = try await bottles.runner(for: name, mode: .headless).wine([steamExe.path, "-shutdown"], cwd: steamFolder)
            for _ in 0..<30 {
                if try await !processes().contains("steam.exe") { break }
                try await Task.sleep(for: .seconds(1))
            }
        }
        try await bottles.kill(name)
    }

    public func restart() async throws -> StartOutcome {
        try await stop()
        return try await start()
    }

    public func status() async throws -> SteamStatus {
        let installed = isInstalled()
        let running = installed ? try await processes() : []
        let logs = steamFolder.appending(path: "logs")
        func tail(_ file: String) -> String {
            guard let handle = try? FileHandle(forReadingFrom: logs.appending(path: file)) else { return "" }
            defer { try? handle.close() }
            let end = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: end > 262_144 ? end - 262_144 : 0)
            return String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        }
        let health = SteamLogs.health(connectionLog: tail("connection_log.txt"), webhelperLog: tail("webhelper.txt"),
                                      bootstrapLog: tail("bootstrap_log.txt"), now: Date())
        return SteamStatus(installed: installed, running: running.contains("steam.exe"),
                           webhelperRunning: running.contains("steamwebhelper.exe"),
                           macSteamRunning: macSteam(), health: health)
    }
}
