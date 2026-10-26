import Foundation
import Testing
@testable import CellarCore

/// The shared Steam bottle over a fake engine, with Outer Wilds "installed" in it. The fake `wine` records each
/// call with the environment that matters, plays Steam (launching it writes a healthy tasklist and, unless told
/// not to, a signed-in connection log) and answers tasklist from a file.
private struct GameRig {
    let tmp: TempRoot
    let calls: URL
    let tasklist: URL
    let noSignIn: URL
    let steam: SteamStore
    let games: GameStore

    init(steamRunning: Bool = true, signedIn: Bool = true, gameRunning: Bool = false, d3dmetal: Bool = true) async throws {
        tmp = try TempRoot(rootName: "Cellar Play")
        calls = tmp.url.appending(path: "calls.txt")
        tasklist = tmp.url.appending(path: "tasklist.csv")
        noSignIn = tmp.url.appending(path: "no-sign-in")
        let steamDir = #""$WINEPREFIX/drive_c/Program Files (x86)/Steam""#
        let wine = """
        #!/bin/sh
        printf "%s | cwd=%s | appid=%s | prepend=%s\\n" "$*" "$(pwd)" "$SteamAppId" "$WINEDLLPATH_PREPEND" >> '\(calls.path)'
        mkdir -p "$WINEPREFIX" && touch "$WINEPREFIX/user.reg"
        case "$1" in
          *SteamSetup.exe) mkdir -p \(steamDir) && touch \(steamDir)/steam.exe ;;
          tasklist) cat '\(tasklist.path)' 2>/dev/null ;;
        esac
        case "$*" in *steam.exe\\ -no-cef-sandbox)
          printf '"steam.exe","32"\\r\\n"steamwebhelper.exe","40"\\r\\n' > '\(tasklist.path)'
          if [ ! -f '\(noSignIn.path)' ]; then
            mkdir -p \(steamDir)/logs
            printf '[%s] [Logged On, 4, 7] [U:1:1] RecvMsgClientLogOnResponse() : processing complete\\r\\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> \(steamDir)/logs/connection_log.txt
          fi ;;
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
        games = GameStore(paths: tmp.paths, steam: steam, signInWait: .seconds(1), pollInterval: .milliseconds(200))
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

@Test func throughSteamProfileUsesApplaunch() async throws {
    let rig = try await GameRig()
    var profile = outerWilds
    profile.launch = .throughSteam
    _ = try await rig.games.play(profile)
    #expect(await rig.waitFor("-applaunch 753640") != nil)
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
