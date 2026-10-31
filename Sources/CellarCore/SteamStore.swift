import Foundation

public enum SteamError: Error, Equatable {
    case notInstalled
    case badInstaller(String)
    case installFailed(String)
    /// Steam ran but its window process (steamwebhelper.exe) never came up, even after one restart.
    case noWindow
    /// Steam for Mac signed in to the account, so Steam signed Cellar's Steam out; restarting would just swap them back.
    case signedInElsewhere
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
        case .signedInElsewhere:
            "no: your account signed in somewhere else (Steam for Mac or another computer), so Steam signed this one out. Run: cellar steam"
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
    /// Steam came up without its window process, so Cellar restarted it once.
    case restartedAfterNoWindow
    /// Steam was signed out because the account signed in somewhere else, so Cellar restarted it to sign back in.
    case signedBackIn
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
    /// How long `tasklist` and `-shutdown` may take before the session counts as stuck.
    let commandTimeout: Duration
    /// How long a fresh Steam may take to bring up its window process before Cellar restarts it once.
    let windowWait: Duration
    let pollInterval: Duration

    public init(paths: CellarPaths, bottles: BottleStore, engines: EngineStore,
                installer: URL = SteamStore.installerURL, engineId: String? = nil,
                macSteam: @escaping @Sendable () -> Bool = MacSteam.isRunning,
                commandTimeout: Duration = .seconds(15),
                windowWait: Duration = .seconds(45), pollInterval: Duration = .seconds(2)) {
        self.paths = paths
        self.bottles = bottles
        self.engines = engines
        self.installer = installer
        self.engineId = engineId
        self.macSteam = macSteam
        self.commandTimeout = commandTimeout
        self.windowWait = windowWait
        self.pollInterval = pollInterval
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
        let size = (try fm.attributesOfItem(atPath: part.path)[.size] as? NSNumber)?.int64Value ?? 0
        if response.expectedContentLength > 0, size != response.expectedContentLength {
            throw SteamError.badInstaller("download cut off at \(size) of \(response.expectedContentLength) bytes")
        }
    }

    /// A Windows program (starts with "MZ") of a plausible size; anything else is never run.
    static func checkInstaller(_ file: URL) throws {
        let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
        guard (1_000_000...20_000_000).contains(size) else { throw SteamError.badInstaller("unexpected size \(size) bytes") }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: 0x40) ?? Data()
        guard head.count == 0x40, head.prefix(2) == Data("MZ".utf8) else { throw SteamError.badInstaller("not a Windows program") }
        // e_lfanew at 0x3C points at the "PE\0\0" signature.
        let peOffset = head[0x3C...0x3F].enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
        guard peOffset < size - 4 else { throw SteamError.badInstaller("not a Windows program") }
        try handle.seek(toOffset: UInt64(peOffset))
        guard try handle.read(upToCount: 4) == Data([0x50, 0x45, 0, 0]) else {
            throw SteamError.badInstaller("not a Windows program")
        }
    }

    // MARK: - Run

    public func processes() async throws -> [String] {
        let result = try await bottles.runner(for: name, mode: .headless)
            .wine(["tasklist", "/fo", "csv", "/nh"], timeout: commandTimeout)
        return result.output.split(whereSeparator: \.isNewline).compactMap { line in
            guard line.hasPrefix("\""), let close = line.dropFirst().firstIndex(of: "\"") else { return nil }
            return line[line.index(after: line.startIndex)..<close].lowercased()
        }
    }

    /// `muted` starts Steam with no sound driver, and so every game it launches: nothing can make a sound on this Mac.
    public func start(muted: Bool = false) async throws -> StartOutcome {
        guard isInstalled() else { throw SteamError.notInstalled }
        var outcome: StartOutcome
        do {
            let running = try await processes()
            if running.contains("steam.exe") && running.contains("steamwebhelper.exe") {
                // A Steam signed out from elsewhere never reconnects by itself; a fresh one signs in with the saved login.
                if signedInElsewhere {
                    if macSteam() { throw SteamError.signedInElsewhere }
                    let wasMuted = gamesMuted
                    try await stop()
                    _ = try await start(muted: muted || wasMuted)
                    return .signedBackIn
                }
                // Steam hands this to the instance that's already running, which shows its window.
                try bottles.runner(for: name, mode: .interactive).spawn([steamExe.path] + Self.launchFlags, cwd: steamFolder)
                return .broughtForward
            }
            // steam.exe without its window process is stuck too: clicking its Dock icon does nothing.
            outcome = running.contains(where: { !Self.wineSystemProcesses.contains($0) })
                ? .clearedStaleStateThenStarted : .started
            // Always end the session first: the check above ran headless (no display driver), and a
            // Steam started inside that session would get no window.
            try await bottles.kill(name)
        } catch WineRunnerError.timedOut {
            // The session doesn't answer: it's stuck.
            try await bottles.kill(name)
            outcome = .clearedStaleStateThenStarted
        }
        try launch(muted: muted)
        if try await windowAppears() { return outcome }

        // Seen after a forced stop: Steam's first start loses its window process once; a second start works.
        try await bottles.kill(name)
        try launch(muted: muted)
        if try await windowAppears() { return .restartedAfterNoWindow }
        throw SteamError.noWindow
    }

    /// Starts a fresh Steam. It runs with D3DMetal when that is imported, because the games Steam launches get their
    /// DLL settings from Steam's own environment: Wine drops WINEDLLOVERRIDES set anywhere in between.
    private func launch(muted: Bool) throws {
        let runner = try bottles.runner(for: name, mode: .interactive)
        var renderer = Renderer.wined3d
        var env = WineEnvironment.make(engine: runner.engine, prefix: runner.prefix, mode: .interactive)
        if let d3dmetal = try D3DMetalStore(paths: paths).current() {
            env = try RendererSetup.environment(.d3dmetal, engine: runner.engine, d3dmetal: d3dmetal, paths: paths, base: env)
            env["ROSETTA_ADVERTISE_AVX"] = "1"
            renderer = .d3dmetal
        }
        env["WINEDLLOVERRIDES", default: ""] += ";\(Self.noOverlay)"
        if muted { env["WINEDLLOVERRIDES", default: ""] += ";\(Self.noSound)" }
        try runner.spawn([steamExe.path] + Self.launchFlags, cwd: steamFolder, environmentOverrides: env)
        try Data((renderer.rawValue + (muted ? " muted" : "")).utf8).write(to: rendererFile)
    }

    /// Keeps Steam's overlay out of the (64-bit) games Steam launches: under Wine its hook can take the game's keyboard
    /// away mid-game (Chants of Sennaar, 2026-10-31). Steam itself is 32-bit and keeps its own DLL.
    static let noOverlay = "gameoverlayrenderer64=d"

    /// The DLL override that leaves a program with no sound driver at all.
    static let noSound = "winecoreaudio.drv=d"

    private var rendererFile: URL { paths.bottle(Self.bottleName).appending(path: "steam-renderer") }

    /// The renderer of the games Steam launches, when Cellar started this Steam (nil after a stop, or never started).
    public var gameRenderer: Renderer? {
        (try? String(contentsOf: rendererFile, encoding: .utf8)).flatMap { Renderer(rawValue: String($0.prefix { $0 != " " })) }
    }

    /// Whether the games Steam launches have no sound driver (Steam was started muted).
    public var gamesMuted: Bool { (try? String(contentsOf: rendererFile, encoding: .utf8))?.hasSuffix(" muted") ?? false }

    /// Waits for steamwebhelper.exe, Steam's window process. A session that doesn't answer counts as "not yet".
    private func windowAppears() async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + windowWait
        while clock.now < deadline {
            try await Task.sleep(for: pollInterval)
            if let running = try? await processes(), running.contains("steamwebhelper.exe") { return true }
        }
        return false
    }

    public func stop() async throws {
        guard isInstalled() else { throw SteamError.notInstalled }
        if (try? await processes())?.contains("steam.exe") == true {
            _ = try? await bottles.runner(for: name, mode: .headless)
                .wine([steamExe.path, "-shutdown"], cwd: steamFolder, timeout: commandTimeout)
            for _ in 0..<30 {
                guard let running = try? await processes(), running.contains("steam.exe") else { break }
                try await Task.sleep(for: .seconds(1))
            }
        }
        try await bottles.kill(name)
        try? FileManager.default.removeItem(at: rendererFile)
    }

    public func restart(muted: Bool = false) async throws -> StartOutcome {
        try await stop()
        return try await start(muted: muted)
    }

    /// Whether Steam's log says it was signed out because the account signed in somewhere else.
    public var signedInElsewhere: Bool {
        if case .signedInElsewhere = health().signIn { true } else { false }
    }

    public func status() async throws -> SteamStatus {
        let installed = isInstalled()
        // A session that doesn't answer in time is reported as not running.
        let running = installed ? ((try? await processes()) ?? []) : []
        return SteamStatus(installed: installed, running: running.contains("steam.exe"),
                           webhelperRunning: running.contains("steamwebhelper.exe"),
                           macSteamRunning: macSteam(), health: health())
    }

    /// Whether Steam's launch of `appid`, asked at `since`, is waiting on the user in the Steam window.
    public func launchWaitingForYou(appid: Int, since: Date) -> Bool {
        SteamLogs.launchWaitingForYou(consoleLog: tail("console_log.txt"), appid: appid, since: since)
    }

    /// The last 256 KB of one of Steam's logs.
    private func tail(_ file: String) -> String {
        guard let handle = try? FileHandle(forReadingFrom: steamFolder.appending(path: "logs").appending(path: file)) else { return "" }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: end > 262_144 ? end - 262_144 : 0)
        return String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
    }

    private func health() -> SteamHealth {
        SteamLogs.health(connectionLog: tail("connection_log.txt"), webhelperLog: tail("webhelper.txt"),
                         bootstrapLog: tail("bootstrap_log.txt"), now: Date())
    }
}
