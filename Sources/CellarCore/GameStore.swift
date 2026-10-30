import Foundation

public enum GameError: Error, Equatable {
    case unknownGame(String)
    case notInstalled(String)
    case stillDownloading(String)
    case steamNotSignedIn
    /// Steam took the launch request but never started the game, even after a restart.
    case steamIgnoredLaunch(String)
    /// Steam ignored the launch, and Cellar left it running because `other` runs in its bottle too.
    case steamIgnoredLaunchBeside(String, other: String)
    /// Steam was still running an installer for the game (DirectX, VC++) when Cellar stopped waiting.
    case steamStillInstalling(String, installer: String)
}

public enum PlayOutcome: Equatable, Sendable {
    /// `restartedSteam`: Steam ignored the first request, so Cellar restarted it and asked again.
    case launched(pid: Int32, restartedSteam: Bool = false)
    case broughtForward
}

/// Starts games from the shared Steam bottle, each with its own renderer, while Steam runs beside them.
public struct GameStore: Sendable {
    let paths: CellarPaths
    let steam: SteamStore
    let signInWait: Duration
    /// How long Steam may take to start the game after being asked.
    let launchWait: Duration
    /// How long a first launch may spend in Steam's installers (DirectX, VC++) before the game.
    let setupWait: Duration
    let pollInterval: Duration

    public init(paths: CellarPaths, steam: SteamStore, signInWait: Duration = .seconds(90),
                launchWait: Duration = .seconds(45), setupWait: Duration = .seconds(600), pollInterval: Duration = .seconds(2)) {
        self.paths = paths
        self.steam = steam
        self.signInWait = signInWait
        self.launchWait = launchWait
        self.setupWait = setupWait
        self.pollInterval = pollInterval
    }

    /// Steam launches the game when it can, so Steam Cloud syncs its saves before and after. That needs a Steam that
    /// Cellar started with the game's renderer, and no extra variables (a check's HUD): otherwise the game starts
    /// directly beside Steam, without cloud sync. `muted` starts the game with no sound driver at all, so it can't make
    /// a sound on this Mac; through Steam only when Steam itself was started muted. `starting` is called once every check
    /// has passed, right before Wine starts anything.
    public func play(_ profile: GameProfile, extraEnvironment: [String: String] = [:], muted: Bool = false,
                     starting: @Sendable () -> Void = {}) async throws -> PlayOutcome {
        let folder: URL
        switch SteamLibrary.state(appid: profile.appid, steamFolder: steam.steamFolder) {
        case .notInstalled: throw GameError.notInstalled(profile.name)
        case .downloading: throw GameError.stillDownloading(profile.name)
        case .installed(let f): folder = f
        }
        let exe = folder.appending(path: profile.exe)
        guard FileManager.default.fileExists(atPath: exe.path) else { throw GameError.notInstalled(profile.name) }
        // D3DMetal ships 64-bit DLLs only. An exe Cellar can't read (a launcher stub) is not refused.
        if profile.renderer == .d3dmetal, let facts = try? ExeFacts.read(exe), !facts.is64Bit {
            throw RendererError.d3dmetalNeeds64Bit(profile.name)
        }

        // Work out the renderer first, so a missing D3DMetal is reported before anything starts.
        let runner = try steam.bottles.runner(for: steam.name, mode: .interactive)
        let base = WineEnvironment.make(engine: runner.engine, prefix: runner.prefix, mode: .interactive)
        var env = try RendererSetup.environment(profile.renderer, engine: runner.engine,
                                                d3dmetal: try D3DMetalStore(paths: paths).current(), paths: paths, base: base)
        env["SteamAppId"] = String(profile.appid)
        env["SteamGameId"] = String(profile.appid)
        env["ROSETTA_ADVERTISE_AVX"] = "1"
        env.merge(extraEnvironment) { $1 }
        if muted { env["WINEDLLOVERRIDES", default: ""] += ";\(SteamStore.noSound)" }
        starting()

        let running = (try? await steam.processes()) ?? []
        if running.contains(exe.lastPathComponent.lowercased()) {
            try runner.spawn([exe.path], cwd: folder, environmentOverrides: env)
            return .broughtForward
        }

        let started = Date()
        let steamUp = running.contains("steam.exe") && running.contains("steamwebhelper.exe")
        if !steamUp { _ = try await steam.start() }
        try await waitForSignIn(after: steamUp ? nil : started)

        if profile.launch == .throughSteam && extraEnvironment.isEmpty && steam.gameRenderer == profile.renderer
            && steam.gamesMuted == muted {
            return try await launchThroughSteam(profile, exe: exe.lastPathComponent.lowercased(), muted: muted)
        }
        return .launched(pid: try runner.spawn([exe.path], cwd: folder, environmentOverrides: env))
    }

    /// Asks Steam to launch the game and waits for it. A Steam that has run for a long time can take the request and do
    /// nothing, with no trace in its logs (2026-10-30); a restarted Steam launches it. So Cellar restarts Steam once,
    /// unless something else runs in its bottle that a restart would kill.
    private func launchThroughSteam(_ profile: GameProfile, exe: String, muted: Bool) async throws -> PlayOutcome {
        let runner = try steam.bottles.runner(for: steam.name, mode: .interactive)
        func ask() throws -> Int32 {
            try runner.spawn([steam.steamExe.path] + SteamStore.launchFlags + ["-applaunch", String(profile.appid)],
                             cwd: steam.steamFolder)
        }
        var before = Set((try? await steam.processes()) ?? [])
        var pid = try ask()
        if try await gameAppears(exe, besides: before) { return .launched(pid: pid) }

        // Never restart Steam, or blame anything, while it is still installing for the game.
        func stillInstalling() async throws {
            if let installer = ((try? await steam.processes()) ?? []).first(where: { Self.isProgram($0) && !before.contains($0) }) {
                throw GameError.steamStillInstalling(profile.name, installer: installer)
            }
        }
        try await stillInstalling()
        if let other = ((try? await steam.processes()) ?? []).first(where: Self.isProgram) {
            throw GameError.steamIgnoredLaunchBeside(profile.name, other: other)
        }
        let restarted = Date()
        _ = try await steam.restart(muted: muted)
        try await waitForSignIn(after: restarted)
        before = Set((try? await steam.processes()) ?? [])
        pid = try ask()
        if try await gameAppears(exe, besides: before) { return .launched(pid: pid, restartedSteam: true) }
        try await stillInstalling()
        throw GameError.steamIgnoredLaunch(profile.name)
    }

    /// A program in Steam's bottle that is neither Wine's nor Steam's own: a game, or an installer Steam runs.
    static func isProgram(_ process: String) -> Bool {
        !SteamStore.wineSystemProcesses.contains(process) && !process.hasPrefix("steam") && process != "gameoverlayui.exe"
    }

    /// Waits `launchWait` for the game. A program that wasn't in `before` is Steam installing something first: while one
    /// runs, the wait goes on, `launchWait` past its last sighting, up to `setupWait` from the ask.
    private func gameAppears(_ exe: String, besides before: Set<String>) async throws -> Bool {
        let clock = ContinuousClock()
        let asked = clock.now
        var deadline = asked + launchWait
        repeat {
            try await Task.sleep(for: pollInterval)
            guard let running = try? await steam.processes() else { continue }
            if running.contains(exe) { return true }
            if running.contains(where: { Self.isProgram($0) && !before.contains($0) }) {
                deadline = min(max(deadline, clock.now + launchWait), asked + setupWait)
            }
        } while clock.now < deadline
        return false
    }

    public func isRunning(_ profile: GameProfile) async throws -> Bool {
        let exe = (profile.exe as NSString).lastPathComponent.lowercased()
        return try await steam.processes().contains(exe)
    }

    /// Steam signs in by itself with the saved login; after a fresh start, only a sign-in from this start counts.
    private func waitForSignIn(after start: Date?) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + signInWait
        repeat {
            if case .signedIn(let since) = try await steam.status().health.signIn,
               start.map({ since >= $0.addingTimeInterval(-2) }) ?? true {
                return
            }
            try await Task.sleep(for: pollInterval)
        } while clock.now < deadline
        throw GameError.steamNotSignedIn
    }
}
