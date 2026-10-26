import Foundation

public enum GameError: Error, Equatable {
    case unknownGame(String)
    case notInstalled(String)
    case stillDownloading(String)
    case steamNotSignedIn
}

public enum PlayOutcome: Equatable, Sendable {
    case launched(pid: Int32)
    case broughtForward
}

/// Starts games from the shared Steam bottle, each with its own renderer, while Steam runs beside them.
public struct GameStore: Sendable {
    let paths: CellarPaths
    let steam: SteamStore
    let signInWait: Duration
    let pollInterval: Duration

    public init(paths: CellarPaths, steam: SteamStore, signInWait: Duration = .seconds(90), pollInterval: Duration = .seconds(2)) {
        self.paths = paths
        self.steam = steam
        self.signInWait = signInWait
        self.pollInterval = pollInterval
    }

    public func play(_ profile: GameProfile, extraEnvironment: [String: String] = [:]) async throws -> PlayOutcome {
        let folder: URL
        switch SteamLibrary.state(appid: profile.appid, steamFolder: steam.steamFolder) {
        case .notInstalled: throw GameError.notInstalled(profile.name)
        case .downloading: throw GameError.stillDownloading(profile.name)
        case .installed(let f): folder = f
        }
        let exe = folder.appending(path: profile.exe)
        guard FileManager.default.fileExists(atPath: exe.path) else { throw GameError.notInstalled(profile.name) }

        // Work out the renderer first, so a missing D3DMetal is reported before anything starts.
        let runner = try steam.bottles.runner(for: steam.name, mode: .interactive)
        let base = WineEnvironment.make(engine: runner.engine, prefix: runner.prefix, mode: .interactive)
        var env = try RendererSetup.environment(profile.renderer, engine: runner.engine,
                                                d3dmetal: try D3DMetalStore(paths: paths).current(), paths: paths, base: base)
        env["SteamAppId"] = String(profile.appid)
        env["SteamGameId"] = String(profile.appid)
        env["ROSETTA_ADVERTISE_AVX"] = "1"
        env.merge(extraEnvironment) { $1 }

        let running = (try? await steam.processes()) ?? []
        if running.contains(exe.lastPathComponent.lowercased()) {
            try runner.spawn([exe.path], cwd: folder, environmentOverrides: env)
            return .broughtForward
        }

        let started = Date()
        let steamUp = running.contains("steam.exe") && running.contains("steamwebhelper.exe")
        if !steamUp { _ = try await steam.start() }
        try await waitForSignIn(after: steamUp ? nil : started)

        switch profile.launch {
        case .direct:
            return .launched(pid: try runner.spawn([exe.path], cwd: folder, environmentOverrides: env))
        case .throughSteam:
            let pid = try runner.spawn([steam.steamExe.path] + SteamStore.launchFlags + ["-applaunch", String(profile.appid)],
                                       cwd: steam.steamFolder, environmentOverrides: env)
            return .launched(pid: pid)
        }
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
