import Foundation
import Synchronization
import Testing
@testable import CellarCore

/// The shared Steam bottle over a fake engine, with Outer Wilds "installed" in it. The fake `wine` records each
/// call with the environment that matters, plays Steam (launching it writes a healthy tasklist and, unless told
/// not to, a signed-in connection log; `-applaunch` adds the game to the tasklist unless Steam is `deaf`, or `stale`
/// until its next start, or runs an installer first when `slowSetup`; `-shutdown` empties it) and answers tasklist from a
/// file.
struct GameRig {
    let tmp: TempRoot
    let calls: URL
    let tasklist: URL
    let noSignIn: URL
    /// Steam ignores launches until it is started again (seen 2026-10-30 after a night of running).
    let stale: URL
    /// Steam ignores every launch.
    let deaf: URL
    /// Steam runs DXSETUP.exe for 3 s before the game starts, as on a first launch.
    let slowSetup: URL
    /// Steam's DXSETUP.exe never finishes.
    let endlessSetup: URL
    let steam: SteamStore
    let games: GameStore

    init(steamRunning: Bool = true, signedIn: Bool = true, gameRunning: Bool = false, d3dmetal: Bool = true) async throws {
        tmp = try TempRoot(rootName: "Cellar Play")
        calls = tmp.url.appending(path: "calls.txt")
        tasklist = tmp.url.appending(path: "tasklist.csv")
        noSignIn = tmp.url.appending(path: "no-sign-in")
        stale = tmp.url.appending(path: "stale")
        deaf = tmp.url.appending(path: "deaf")
        slowSetup = tmp.url.appending(path: "slow-setup")
        endlessSetup = tmp.url.appending(path: "endless-setup")
        let steamDir = #""$WINEPREFIX/drive_c/Program Files (x86)/Steam""#
        let wine = """
        #!/bin/sh
        printf "%s | cwd=%s | appid=%s | prepend=%s | overrides=%s\\n" "$*" "$(pwd)" "$SteamAppId" "$WINEDLLPATH_PREPEND" "$WINEDLLOVERRIDES" >> '\(calls.path)'
        mkdir -p "$WINEPREFIX" && touch "$WINEPREFIX/user.reg"
        case "$1" in
          *SteamSetup.exe) mkdir -p \(steamDir) && touch \(steamDir)/steam.exe ;;
          tasklist) cat '\(tasklist.path)' 2>/dev/null ;;
        esac
        case "$*" in
          *steam.exe\\ -no-cef-sandbox)
            printf '"steam.exe","32"\\r\\n"steamwebhelper.exe","40"\\r\\n' > '\(tasklist.path)'
            rm -f '\(stale.path)'
            if [ ! -f '\(noSignIn.path)' ]; then
              mkdir -p \(steamDir)/logs
              printf '[%s] [Logged On, 4, 7] [U:1:1] RecvMsgClientLogOnResponse() : processing complete\\r\\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> \(steamDir)/logs/connection_log.txt
            fi ;;
          *-applaunch\\ *)
            if [ -f '\(stale.path)' ] || [ -f '\(deaf.path)' ]; then
              :
            elif [ -f '\(endlessSetup.path)' ]; then
              printf '"DXSETUP.exe","70"\\r\\n' >> '\(tasklist.path)'
            elif [ -f '\(slowSetup.path)' ]; then
              printf '"DXSETUP.exe","70"\\r\\n' >> '\(tasklist.path)'
              (sleep 3; grep -v DXSETUP '\(tasklist.path)' > '\(tasklist.path).new'; mv '\(tasklist.path).new' '\(tasklist.path)'
               printf '"OuterWilds.exe","50"\\r\\n' >> '\(tasklist.path)') &
            else
              printf '"OuterWilds.exe","50"\\r\\n' >> '\(tasklist.path)'
            fi ;;
          *-shutdown) : > '\(tasklist.path)' ;;
        esac
        exit 0
        """
        try FakeEngine.installed(id: "fake", in: tmp.paths.engines, wine: wine, wineserver: "#!/bin/sh\nexit 0\n")
        let engines = EngineStore(paths: tmp.paths, discard: TempRoot.discard)
        let bottles = BottleStore(paths: tmp.paths, engines: engines, discard: TempRoot.discard)
        let installer = tmp.url.appending(path: "SteamSetup.exe")
        var pe = Data(count: 2_000_000); pe[0] = 0x4D; pe[1] = 0x5A; pe[0x3C] = 0x80; pe[0x80] = 0x50; pe[0x81] = 0x45
        try pe.write(to: installer)
        steam = SteamStore(paths: tmp.paths, bottles: bottles, engines: engines, installer: installer, engineId: "fake",
                           macSteam: { false }, commandTimeout: .seconds(2), windowWait: .seconds(3), pollInterval: .milliseconds(200))
        try await steam.install()

        let game = steam.steamFolder.appending(path: "steamapps/common/Outer Wilds")
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: game.appending(path: "OuterWilds.exe"))
        try Data(appManifest(appid: 753640, name: "Outer Wilds", installdir: "Outer Wilds", stateFlags: 4).utf8)
            .write(to: steam.steamFolder.appending(path: "steamapps/appmanifest_753640.acf"))

        if d3dmetal {
            let folder = tmp.paths.d3dmetal.appending(path: "3.0")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder.cellar.encode(D3DMetalImport(version: "3.0", importedAt: Date(), source: "/x.dmg"))
                .write(to: folder.appending(path: "IMPORT.json"))
        }
        var running: [String] = []
        if steamRunning { running += ["steam.exe", "steamwebhelper.exe"] }
        if gameRunning { running.append("outerwilds.exe") }
        try Data(running.map { "\"\($0)\",\"1\"\r\n" }.joined().utf8).write(to: tasklist)
        if steamRunning && signedIn {
            let logs = steam.steamFolder.appending(path: "logs")
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            try Data(SteamLogFixtures.connectionSignedIn.utf8).write(to: logs.appending(path: "connection_log.txt"))
        }
        if !signedIn { try Data().write(to: noSignIn) }
        try? FileManager.default.removeItem(at: calls)
        games = GameStore(paths: tmp.paths, steam: steam, signInWait: .seconds(1), launchWait: .seconds(2),
                          setupWait: .seconds(5), pollInterval: .milliseconds(200))
    }

    var lines: [String] { ((try? String(contentsOf: calls, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }

    func waitFor(_ text: String) async -> String? {
        for _ in 0..<50 {
            if let line = lines.first(where: { $0.contains(text) }) { return line }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }
}

private let outerWilds = GameProfile(id: "outer-wilds", name: "Outer Wilds", appid: 753640, exe: "OuterWilds.exe",
                                     renderer: .d3dmetal, saves: nil, launch: .direct)

@Test func playLaunchesTheExeDirectlyWithTheRendererAndAppId() async throws {
    let rig = try await GameRig()
    let outcome = try await rig.games.play(outerWilds)
    guard case .launched = outcome else { Issue.record("\(outcome)"); return }
    let line = try #require(await rig.waitFor("OuterWilds.exe"))
    #expect(line.contains("cwd=\(rig.steam.steamFolder.path)/steamapps/common/Outer Wilds") || line.contains("/steamapps/common/Outer Wilds |"))
    #expect(line.contains("appid=753640"))
    #expect(line.contains("prepend=\(rig.tmp.paths.d3dmetal.path)/3.0/wine"))
}

@Test func playStartsSteamFirstWhenItIsNotRunning() async throws {
    let rig = try await GameRig(steamRunning: false)
    _ = try await rig.games.play(outerWilds)
    let steamLine = try #require(await rig.waitFor("steam.exe -no-cef-sandbox"))
    let gameLine = try #require(await rig.waitFor("OuterWilds.exe"))
    #expect(rig.lines.firstIndex(of: steamLine)! < rig.lines.firstIndex(of: gameLine)!)
}

@Test func playStopsWithASentenceWhenSteamNeverSignsIn() async throws {
    let rig = try await GameRig(steamRunning: false, signedIn: false)
    let t0 = Date()
    await #expect(throws: GameError.steamNotSignedIn) { try await rig.games.play(outerWilds) }
    #expect(Date().timeIntervalSince(t0) < 15)
    #expect(!rig.lines.contains { $0.contains("OuterWilds.exe") })
}

@Test func secondPlayBringsTheGameForward() async throws {
    let rig = try await GameRig(gameRunning: true)
    #expect(try await rig.games.play(outerWilds) == .broughtForward)
}

@Test func notInstalledGameIsRefusedWithoutStartingWine() async throws {
    let rig = try await GameRig()
    let other = GameProfile(id: "journey", name: "Journey", appid: 638230, exe: "Journey.exe", renderer: .d3dmetal)
    await #expect(throws: GameError.notInstalled("Journey")) { try await rig.games.play(other) }
    #expect(!rig.lines.contains { $0.contains("Journey.exe") })
}

@Test func d3dmetalGameWithoutImportSaysHowToImport() async throws {
    let rig = try await GameRig(d3dmetal: false)
    await #expect(throws: RendererError.d3dmetalNotImported) { try await rig.games.play(outerWilds) }
}

private var throughSteam: GameProfile {
    var profile = outerWilds
    profile.launch = .throughSteam
    return profile
}

@Test func steamStartedByCellarRunsWithD3DMetalForItsGames() async throws {
    let rig = try await GameRig(steamRunning: false)
    _ = try await rig.steam.start()
    let line = try #require(await rig.waitFor("steam.exe -no-cef-sandbox"))
    #expect(line.contains("prepend=\(rig.tmp.paths.d3dmetal.path)/3.0/wine"))
    #expect(line.contains("d3d11,d3d12,d3d10core,dxgi=b"))
    #expect(rig.steam.gameRenderer == .d3dmetal)
}

@Test func steamWithoutD3DMetalRunsItsGamesOnWinesOwnRenderer() async throws {
    let rig = try await GameRig(steamRunning: false, d3dmetal: false)
    _ = try await rig.steam.start()
    let line = try #require(await rig.waitFor("steam.exe -no-cef-sandbox"))
    #expect(line.contains("prepend= |"))
    #expect(rig.steam.gameRenderer == .wined3d)
}

@Test func stoppingSteamForgetsItsRenderer() async throws {
    let rig = try await GameRig(steamRunning: false)
    _ = try await rig.steam.start()
    try await rig.steam.stop()
    #expect(rig.steam.gameRenderer == nil)
}

@Test func steamLaunchesTheGameSoItsCloudSaveSyncs() async throws {
    let rig = try await GameRig(steamRunning: false)
    guard case .launched = try await rig.games.play(throughSteam) else { Issue.record("not launched"); return }
    let line = try #require(await rig.waitFor("-applaunch 753640"))
    #expect(line.contains("prepend= |"))  // the game gets D3DMetal from Steam, not from this call
    try await Task.sleep(for: .milliseconds(300))
    #expect(!rig.lines.contains { $0.hasPrefix(rig.steam.steamFolder.path + "/steamapps") || $0.contains("OuterWilds.exe |") })
}

@Test func steamStartedOutsideCellarMeansADirectStart() async throws {
    let rig = try await GameRig()  // Steam already running, renderer unknown
    _ = try await rig.games.play(throughSteam)
    let line = try #require(await rig.waitFor("OuterWilds.exe"))
    #expect(line.contains("prepend=\(rig.tmp.paths.d3dmetal.path)/3.0/wine"))
    #expect(!rig.lines.contains { $0.contains("-applaunch") })
}

@Test func aCheckStartsTheGameItselfToGiveItTheHUD() async throws {
    let rig = try await GameRig(steamRunning: false)
    _ = try await rig.games.play(throughSteam, extraEnvironment: ["MTL_HUD_ENABLED": "1"])
    #expect(await rig.waitFor("OuterWilds.exe") != nil)
    #expect(!rig.lines.contains { $0.contains("-applaunch") })
}

@Test func mutedPlayHasNoSoundDriverButKeepsTheRenderer() async throws {
    let rig = try await GameRig()
    _ = try await rig.games.play(outerWilds, muted: true)
    let line = try #require(await rig.waitFor("OuterWilds.exe"))
    #expect(line.contains("winecoreaudio.drv=d"))
    #expect(line.contains("d3d11,d3d12,d3d10core,dxgi=b"))
}

@Test func aMutedSteamLaunchesOnlyMutedGames() async throws {
    let rig = try await GameRig(steamRunning: false)
    _ = try await rig.steam.start(muted: true)
    let steamLine = try #require(await rig.waitFor("steam.exe -no-cef-sandbox"))
    #expect(steamLine.contains("winecoreaudio.drv=d"))
    #expect(rig.steam.gamesMuted)
    // A muted play goes through the muted Steam; a play with sound must not, so it starts the game itself.
    _ = try await rig.games.play(throughSteam, muted: true)
    #expect(await rig.waitFor("-applaunch 753640") != nil)
    _ = try await rig.games.play(throughSteam)
    #expect(await rig.waitFor("OuterWilds.exe |") != nil)
}

@Test func steamWithSoundNeverLaunchesAMutedGame() async throws {
    let rig = try await GameRig(steamRunning: false)
    _ = try await rig.games.play(throughSteam, muted: true)
    let line = try #require(await rig.waitFor("OuterWilds.exe |"))
    #expect(line.contains("winecoreaudio.drv=d"))
    #expect(!rig.lines.contains { $0.contains("-applaunch") })
}

@Test func playWaitsUntilSteamHasReallyStartedTheGame() async throws {
    let rig = try await GameRig(steamRunning: false)
    guard case .launched(_, let restarted) = try await rig.games.play(throughSteam) else { Issue.record("not launched"); return }
    #expect(!restarted)
    #expect(try await rig.games.isRunning(throughSteam))
    #expect(rig.lines.filter { $0.contains("steam.exe -no-cef-sandbox |") }.count == 1)
}

@Test func steamThatIgnoresTheLaunchIsRestartedOnceAndAskedAgain() async throws {
    let rig = try await GameRig(steamRunning: false)
    _ = try await rig.steam.start()
    try Data().write(to: rig.stale)
    guard case .launched(_, let restarted) = try await rig.games.play(throughSteam) else { Issue.record("not launched"); return }
    #expect(restarted)
    #expect(rig.lines.filter { $0.contains("-applaunch 753640") }.count == 2)
    #expect(rig.lines.contains { $0.contains("-shutdown") })
    #expect(rig.steam.gameRenderer == .d3dmetal)  // the new Steam still gives its games D3DMetal
}

@Test func steamThatNeverLaunchesTheGameEndsWithASentence() async throws {
    let rig = try await GameRig(steamRunning: false)
    try Data().write(to: rig.deaf)
    await #expect(throws: GameError.steamIgnoredLaunch("Outer Wilds")) { try await rig.games.play(throughSteam) }
    #expect(rig.lines.filter { $0.contains("-applaunch 753640") }.count == 2)
}

@Test func steamIsNotRestartedUnderAnotherRunningGame() async throws {
    let rig = try await GameRig(steamRunning: false)
    _ = try await rig.steam.start()
    try Data().write(to: rig.stale)
    let handle = try FileHandle(forWritingTo: rig.tasklist)
    try handle.seekToEnd(); try handle.write(contentsOf: Data("\"Animal Well.exe\",\"60\"\r\n".utf8)); try handle.close()
    await #expect(throws: GameError.steamIgnoredLaunchBeside("Outer Wilds", other: "animal well.exe")) {
        try await rig.games.play(throughSteam)
    }
    #expect(!rig.lines.contains { $0.contains("-shutdown") })
}

@Test func aMutedSteamComesBackMutedAfterARestart() async throws {
    let rig = try await GameRig(steamRunning: false)
    _ = try await rig.steam.start(muted: true)
    try Data().write(to: rig.stale)
    _ = try await rig.games.play(throughSteam, muted: true)
    #expect(rig.steam.gamesMuted)
    #expect(rig.lines.filter { $0.contains("steam.exe -no-cef-sandbox |") }.allSatisfy { $0.contains("winecoreaudio.drv=d") })
}

@Test func firstLaunchInstallersAreWaitedForNotRestarted() async throws {
    let rig = try await GameRig(steamRunning: false)
    try Data().write(to: rig.slowSetup)
    guard case .launched(_, let restarted) = try await rig.games.play(throughSteam) else { Issue.record("not launched"); return }
    #expect(!restarted)
    #expect(!rig.lines.contains { $0.contains("-shutdown") })
}

@Test func aGameAlreadyRunningIsNotTakenForAnInstaller() async throws {
    let rig = try await GameRig(steamRunning: false)
    _ = try await rig.steam.start()
    try Data().write(to: rig.stale)
    let handle = try FileHandle(forWritingTo: rig.tasklist)
    try handle.seekToEnd(); try handle.write(contentsOf: Data("\"Animal Well.exe\",\"60\"\r\n".utf8)); try handle.close()
    let t0 = Date()
    await #expect(throws: GameError.steamIgnoredLaunchBeside("Outer Wilds", other: "animal well.exe")) {
        try await rig.games.play(throughSteam)
    }
    #expect(Date().timeIntervalSince(t0) < 8)
}

@Test func thirtyTwoBitExeIsRefusedForD3DMetal() async throws {
    let rig = try await GameRig()
    try PEFixture.make(machine: 0x14c, imports: ["d3d11.dll"])
        .write(to: rig.steam.steamFolder.appending(path: "steamapps/common/Outer Wilds/OuterWilds.exe"))
    await #expect(throws: RendererError.d3dmetalNeeds64Bit("Outer Wilds")) { try await rig.games.play(outerWilds) }
    #expect(!rig.lines.contains { $0.contains("OuterWilds.exe") })
}

@Test func unreadableExeIsStillStarted() async throws {
    let rig = try await GameRig()  // its OuterWilds.exe is just "MZ"
    _ = try await rig.games.play(outerWilds)
    #expect(await rig.waitFor("OuterWilds.exe |") != nil)
}

@Test func startingIsAnnouncedOnlyForAGameThatCanStart() async throws {
    let rig = try await GameRig()
    let count = Mutex(0)
    let other = GameProfile(id: "journey", name: "Journey", appid: 638230, exe: "Journey.exe", renderer: .d3dmetal)
    await #expect(throws: GameError.notInstalled("Journey")) {
        try await rig.games.play(other, starting: { count.withLock { $0 += 1 } })
    }
    #expect(count.withLock { $0 } == 0)
    _ = try await rig.games.play(outerWilds, starting: { count.withLock { $0 += 1 } })
    #expect(count.withLock { $0 } == 1)
}

@Test func anInstallerThatNeverEndsIsNotKilledOrBlamed() async throws {
    let rig = try await GameRig(steamRunning: false)
    try Data().write(to: rig.endlessSetup)
    await #expect(throws: GameError.steamStillInstalling("Outer Wilds", installer: "dxsetup.exe")) {
        try await rig.games.play(throughSteam)
    }
    #expect(!rig.lines.contains { $0.contains("-shutdown") })
}

@Test func playSignsSteamBackInWhenItWasSignedOutElsewhere() async throws {
    let rig = try await GameRig()
    try Data(SteamLogFixtures.connectionReplaced.utf8)
        .write(to: rig.steam.steamFolder.appending(path: "logs/connection_log.txt"))
    guard case .launched = try await rig.games.play(throughSteam) else { Issue.record("not launched"); return }
    #expect(rig.lines.contains { $0.contains("-shutdown") })
    #expect(rig.lines.filter { $0.contains("steam.exe -no-cef-sandbox |") }.count == 1)
}
