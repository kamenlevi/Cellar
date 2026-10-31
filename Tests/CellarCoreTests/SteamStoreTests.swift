import Foundation
import Testing
@testable import CellarCore

/// A Steam bottle over a fake engine. The fake `wine` records every call, installs a fake Steam when
/// SteamSetup.exe runs with /S, answers `tasklist` from a file, and empties that file on `-shutdown`.
private struct SteamRig {
    let tmp: TempRoot
    let calls: URL
    let serverCalls: URL
    let tasklist: URL
    let hang: URL
    let noWindow: URL
    let noWindowOnce: URL
    let steamOverrides: URL
    let wine: String
    let wineserver: String
    let bottles: BottleStore
    let engines: EngineStore

    init(installerInstalls: Bool = true) throws {
        tmp = try TempRoot(rootName: "Cellar Steam")
        calls = tmp.url.appending(path: "calls.txt")
        serverCalls = tmp.url.appending(path: "server-calls.txt")
        tasklist = tmp.url.appending(path: "tasklist.csv")
        hang = tmp.url.appending(path: "hang")
        noWindow = tmp.url.appending(path: "no-window")
        noWindowOnce = tmp.url.appending(path: "no-window-once")
        steamOverrides = tmp.url.appending(path: "steam-overrides.txt")
        let install = installerInstalls
            ? #"mkdir -p "$WINEPREFIX/drive_c/Program Files (x86)/Steam" && touch "$WINEPREFIX/drive_c/Program Files (x86)/Steam/steam.exe""#
            : "true"
        wine = """
        #!/bin/sh
        printf "%s\\n" "$*" >> '\(calls.path)'
        mkdir -p "$WINEPREFIX" && touch "$WINEPREFIX/user.reg"
        case "$1" in
          *SteamSetup.exe) [ "$2" = "/S" ] && \(install) ;;
          tasklist) [ -f '\(hang.path)' ] && sleep 30; cat '\(tasklist.path)' 2>/dev/null ;;
        esac
        [ "$2" = "-shutdown" ] && rm -f '\(tasklist.path)'
        case "$*" in *-no-cef-sandbox*)
          rm -f '\(hang.path)'
          printf "%s\\n" "$WINEDLLOVERRIDES" >> '\(steamOverrides.path)'
          if [ -f '\(noWindow.path)' ]; then printf '"steam.exe","32"\r\n' > '\(tasklist.path)'
          elif [ -f '\(noWindowOnce.path)' ]; then rm -f '\(noWindowOnce.path)'; printf '"steam.exe","32"\r\n' > '\(tasklist.path)'
          else printf '"steam.exe","32"\r\n"steamwebhelper.exe","40"\r\n' > '\(tasklist.path)'; fi ;;
        esac
        exit 0
        """
        wineserver = "#!/bin/sh\nprintf \"%s\\n\" \"$*\" >> '\(serverCalls.path)'\n"
        try FakeEngine.installed(id: "fake", in: tmp.paths.engines, wine: wine, wineserver: wineserver)
        engines = EngineStore(paths: tmp.paths, discard: TempRoot.discard)
        bottles = BottleStore(paths: tmp.paths, engines: engines, discard: TempRoot.discard)
    }

    func store(installer: URL? = nil, macSteam: Bool = false, manifest: EngineManifest? = nil,
               announce: @escaping @Sendable (String) -> Void = { _ in }) throws -> SteamStore {
        let source = try installer ?? fakeInstaller()
        return SteamStore(paths: tmp.paths, bottles: bottles, engines: engines,
                          installer: source, engineId: "fake", manifest: manifest, announce: announce,
                          macSteam: { macSteam }, commandTimeout: .seconds(2),
                          windowWait: .seconds(3), pollInterval: .milliseconds(200))
    }

    func fakeInstaller(_ body: Data? = nil) throws -> URL {
        let url = tmp.url.appending(path: "src/SteamSetup.exe")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (body ?? SteamRig.peFile(size: 2_000_000)).write(to: url)
        return url
    }

    /// "MZ", e_lfanew = 0x80 at 0x3C, "PE\0\0" at 0x80, padded to `size`.
    static func peFile(size: Int, peSignature: Bool = true) -> Data {
        var d = Data(count: size)
        d[0] = 0x4D; d[1] = 0x5A
        d[0x3C] = 0x80
        if peSignature { d[0x80] = 0x50; d[0x81] = 0x45 }
        return d
    }

    func lines(_ url: URL) -> [String] {
        ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    func setTasklist(_ names: [String]) throws {
        // Real tasklist output has Windows line endings.
        let csv = names.map { "\"\($0)\",\"32\",\"Console\",\"1\",\"24,512 K\"" }.joined(separator: "\r\n")
        try Data((csv + "\r\n").utf8).write(to: tasklist)
    }

    func installedStore(macSteam: Bool = false, manifest: EngineManifest? = nil,
                        announce: @escaping @Sendable (String) -> Void = { _ in }) async throws -> SteamStore {
        let s = try store(macSteam: macSteam, manifest: manifest, announce: announce)
        try await s.install()
        try? FileManager.default.removeItem(at: calls)
        try? FileManager.default.removeItem(at: serverCalls)
        return s
    }

    func waitForCall(containing text: String) async -> Bool {
        for _ in 0..<50 {
            if lines(calls).contains(where: { $0.contains(text) }) { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }
}

// MARK: - Task 4: install

@Test func installCreatesTheSteamBottleAndRunsTheInstallerSilently() async throws {
    let rig = try SteamRig()
    let steam = try rig.store()
    try await steam.install()
    #expect(try rig.bottles.list().map(\.name) == ["Steam"])
    #expect(steam.isInstalled())
    #expect(rig.lines(rig.calls).contains { $0.hasSuffix("SteamSetup.exe /S") })
    let downloads = (try? FileManager.default.contentsOfDirectory(atPath: rig.tmp.paths.downloads.path)) ?? []
    #expect(downloads.isEmpty, "\(downloads)")
}

@Test(arguments: ["<html>Access denied</html>", "MZ"])
func badInstallerIsNeverRun(_ body: String) async throws {
    let rig = try SteamRig()
    let steam = try rig.store(installer: try rig.fakeInstaller(Data(body.utf8)))
    await #expect(throws: SteamError.self) { try await steam.install() }
    #expect(!rig.lines(rig.calls).contains { $0.contains("SteamSetup.exe") })
    let downloads = (try? FileManager.default.contentsOfDirectory(atPath: rig.tmp.paths.downloads.path)) ?? []
    #expect(downloads.isEmpty, "\(downloads)")
}

@Test func installerThatInstallsNothingFails() async throws {
    let rig = try SteamRig(installerInstalls: false)
    let steam = try rig.store()
    do {
        try await steam.install()
        Issue.record("install should have failed")
    } catch SteamError.installFailed {
    }
}

@Test func installTwiceIsANoOp() async throws {
    let rig = try SteamRig()
    let steam = try await rig.installedStore()
    try await steam.install()
    #expect(rig.lines(rig.calls).isEmpty)
}

@Test func steamExeIsFoundWhateverItsCase() async throws {
    let rig = try SteamRig()
    let steam = try await rig.installedStore()
    let folder = steam.steamFolder
    try FileManager.default.moveItem(at: folder.appending(path: "steam.exe"), to: folder.appending(path: "Steam.exe"))
    #expect(steam.steamExe.lastPathComponent == "Steam.exe")
    #expect(steam.isInstalled())
}

// MARK: - Task 5: start, stop, status

@Test func startWhenNothingRunsSpawnsSteamWithTheSandboxFlag() async throws {
    let rig = try SteamRig()
    let steam = try await rig.installedStore()
    #expect(try await steam.start() == .started)
    #expect(await rig.waitForCall(containing: "steam.exe -no-cef-sandbox"))
    #expect(!rig.lines(rig.calls).contains { $0.contains("-silent") })
    // The check ran headless (no display driver); Steam must not join that session.
    #expect(rig.lines(rig.serverCalls) == ["-k", "-w"])
}

@Test func gamesSteamLaunchesNeverLoadSteamsOverlay() async throws {
    // The overlay's hook took Chants of Sennaar's keyboard away mid-game (2026-10-31); started without it, keys worked.
    let rig = try SteamRig()
    let steam = try await rig.installedStore()
    _ = try await steam.start(muted: true)
    let overrides = rig.lines(rig.steamOverrides).last ?? ""
    #expect(overrides.contains("gameoverlayrenderer64=d"))
    #expect(overrides.contains(SteamStore.noSound))
}

/// "fake-c2" replaces the rig's "fake": the same Wine with fixes, as sikarugir-10.0_6-c2 replaces c1.
private func replacingManifest() -> EngineManifest {
    EngineManifest(engines: [EngineEntry(id: "fake-c2", wineVersion: "10.0", url: URL(string: "https://github.com/kamenlevi/Cellar")!,
                                         sha256: String(repeating: "0", count: 64), size: 1, isDefault: true, replaces: ["fake"])])
}

@Test func aFreshSteamMovesToTheEngineThatReplacesItsOwn() async throws {
    let rig = try SteamRig()
    let steam = try await rig.installedStore(manifest: replacingManifest())
    try FakeEngine.installed(id: "fake-c2", in: rig.tmp.paths.engines, wine: rig.wine, wineserver: rig.wineserver)
    _ = try await steam.start()
    #expect(try rig.bottles.info(BottleName(SteamStore.bottleName)).engineId == "fake-c2")
}

@Test func steamStillStartsWhenTheNewerEngineCannotBeDownloaded() async throws {
    // Offline, a captive portal, a GitHub outage: Steam starts on the engine it has (final review, 2026-10-31).
    let rig = try SteamRig()
    let missing = rig.tmp.url.appending(path: "nowhere/engine.tar.xz")
    let manifest = EngineManifest(engines: [EngineEntry(id: "fake-c2", wineVersion: "10.0", url: missing,
                                                        sha256: String(repeating: "0", count: 64), size: 254_163_984,
                                                        isDefault: true, replaces: ["fake"])])
    let said = Said()
    let steam = try await rig.installedStore(manifest: manifest, announce: said.add)
    _ = try await steam.start()
    #expect(try rig.bottles.info(BottleName(SteamStore.bottleName)).engineId == "fake")
    #expect(said.lines.contains { $0.contains("fake-c2") && $0.contains("254 MB") })
    #expect(said.lines.contains { $0.contains("staying on fake") })
}

@Test func aRunningSteamKeepsItsEngine() async throws {
    // Swapping the engine under live Wine processes isn't safe; the next fresh start moves it.
    let rig = try SteamRig()
    let steam = try await rig.installedStore(manifest: replacingManifest())
    try FakeEngine.installed(id: "fake-c2", in: rig.tmp.paths.engines, wine: rig.wine, wineserver: rig.wineserver)
    try rig.setTasklist(["steam.exe", "steamwebhelper.exe"])
    #expect(try await steam.start() == .broughtForward)
    #expect(try rig.bottles.info(BottleName(SteamStore.bottleName)).engineId == "fake")
}

@Test func startWhenSteamRunsBringsItForward() async throws {
    let rig = try SteamRig()
    let steam = try await rig.installedStore()
    try rig.setTasklist(["steam.exe", "steamwebhelper.exe"])
    #expect(try await steam.start() == .broughtForward)
    #expect(rig.lines(rig.serverCalls).isEmpty)
}

@Test func startClearsStaleStateFirst() async throws {
    let rig = try SteamRig()
    let steam = try await rig.installedStore()
    try rig.setTasklist(["explorer.exe", "services.exe", "steamwebhelper.exe"])
    #expect(try await steam.start() == .clearedStaleStateThenStarted)
    #expect(rig.lines(rig.serverCalls).first == "-k")
    #expect(await rig.waitForCall(containing: "steam.exe -no-cef-sandbox"))
}

@Test func wineSystemProcessesAloneAreNotAStuckSession() async throws {
    let rig = try SteamRig()
    let steam = try await rig.installedStore()
    try rig.setTasklist(["tasklist.exe", "services.exe", "explorer.exe", "plugplay.exe", "winedevice.exe", "svchost.exe", "rpcss.exe", "conhost.exe"])
    #expect(try await steam.start() == .started)
    #expect(rig.lines(rig.serverCalls) == ["-k", "-w"])
}

@Test func stopShutsDownGracefullyThenKills() async throws {
    let rig = try SteamRig()
    let steam = try await rig.installedStore()
    try rig.setTasklist(["steam.exe"])
    try await steam.stop()
    #expect(rig.lines(rig.calls).contains { $0.hasSuffix("steam.exe -shutdown") })
    #expect(rig.lines(rig.serverCalls) == ["-k", "-w"])
}

@Test func statusCombinesProcessesAndLogs() async throws {
    let rig = try SteamRig()
    let steam = try await rig.installedStore(macSteam: true)
    let logs = steam.steamFolder.appending(path: "logs")
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    try Data(SteamLogFixtures.connectionSignedIn.utf8).write(to: logs.appending(path: "connection_log.txt"))
    try Data(SteamLogFixtures.webhelperHealthy.utf8).write(to: logs.appending(path: "webhelper.txt"))
    try rig.setTasklist(["steam.exe", "steamwebhelper.exe"])
    let s = try await steam.status()
    #expect(s.installed && s.running && s.webhelperRunning && s.macSteamRunning)
    #expect(s.health.signIn == .signedIn(since: SteamLogFixtures.local("2026-08-17 00:22:49")))
    #expect(!s.health.crashLoop)
}

@Test func startOnUninstalledThrows() async throws {
    let rig = try SteamRig()
    await #expect(throws: SteamError.notInstalled) { try await rig.store().start() }
}

// MARK: - Task 6: status lines

@Test func statusLinesNeverShowAccountIds() {
    let s = SteamStatus(installed: true, running: true, webhelperRunning: true, macSteamRunning: false,
                        health: SteamLogs.health(connectionLog: SteamLogFixtures.connectionSignedIn,
                                                 webhelperLog: SteamLogFixtures.webhelperCrashLoop,
                                                 bootstrapLog: SteamLogFixtures.bootstrap,
                                                 now: SteamLogFixtures.local("2026-08-11 16:39:30")))
    let lines = s.lines()
    #expect(lines.count == 7)
    #expect(lines.first == "Installed: yes")
    #expect(lines.allSatisfy { !$0.contains("[U:1:") })
    #expect(lines.contains { $0.hasPrefix("Crash loop: YES — 6 web-helper starts in 10 minutes") })
}

// MARK: - Final review fixes

@Test func installerWithoutAPESignatureIsNeverRun() async throws {
    let rig = try SteamRig()
    let steam = try rig.store(installer: try rig.fakeInstaller(SteamRig.peFile(size: 2_000_000, peSignature: false)))
    await #expect(throws: SteamError.self) { try await steam.install() }
    #expect(!rig.lines(rig.calls).contains { $0.contains("SteamSetup.exe") })
}

@Test func aHungSessionIsTreatedAsStuckInsteadOfHangingForever() async throws {
    let rig = try SteamRig()
    let steam = try await rig.installedStore()
    try Data().write(to: rig.hang)
    let t0 = Date()
    #expect(try await steam.start() == .clearedStaleStateThenStarted)
    #expect(Date().timeIntervalSince(t0) < 15)
    #expect(rig.lines(rig.serverCalls).first == "-k")
}

@Test func statusOfAHungSessionReturns() async throws {
    let rig = try SteamRig()
    let steam = try await rig.installedStore()
    try Data().write(to: rig.hang)
    let t0 = Date()
    let s = try await steam.status()
    #expect(Date().timeIntervalSince(t0) < 15)
    #expect(s.installed && !s.running)
}

@Test func processListWithWindowsLineEndingsFindsEveryProcess() async throws {
    let rig = try SteamRig()
    let steam = try await rig.installedStore()
    try rig.setTasklist(["plugplay.exe", "explorer.exe", "steam.exe", "steamwebhelper.exe"])
    #expect(try await steam.processes() == ["plugplay.exe", "explorer.exe", "steam.exe", "steamwebhelper.exe"])
}

// MARK: - Step 5 of Kamen's checklist: Steam up, but its window process gone

/// Collects what SteamStore says.
private final class Said: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []
    var lines: [String] { lock.withLock { _lines } }
    func add(_ line: String) { lock.withLock { _lines.append(line) } }
}

private func spawns(_ rig: SteamRig) -> Int { rig.lines(rig.calls).filter { $0.contains("-no-cef-sandbox") }.count }

@Test func steamThatComesUpWithoutItsWindowIsRestartedOnce() async throws {
    let rig = try SteamRig()
    let steam = try await rig.installedStore()
    try Data().write(to: rig.noWindowOnce)
    #expect(try await steam.start() == .restartedAfterNoWindow)
    #expect(spawns(rig) == 2)
    #expect(try await steam.processes().contains("steamwebhelper.exe"))
}

@Test func steamThatNeverShowsItsWindowEndsInAClearError() async throws {
    let rig = try SteamRig()
    let steam = try await rig.installedStore()
    try Data().write(to: rig.noWindow)
    await #expect(throws: SteamError.noWindow) { try await steam.start() }
    #expect(spawns(rig) == 2)
}

@Test func runningSteamWithoutItsWindowIsNotJustBroughtForward() async throws {
    // Kamen's state after the forced stop: steam.exe alive, steamwebhelper.exe dead, Dock click does nothing.
    let rig = try SteamRig()
    let steam = try await rig.installedStore()
    try rig.setTasklist(["steam.exe", "steamerrorreporter64.exe"])
    #expect(try await steam.start() == .clearedStaleStateThenStarted)
    #expect(rig.lines(rig.serverCalls).first == "-k")
    #expect(spawns(rig) == 1)
}

@Test func noWindowErrorSaysWhatToDo() {
    #expect(SteamError.noWindow.errorDescription == "Steam started but its window never appeared, even after one automatic restart.")
    #expect(SteamError.noWindow.recoverySuggestion == "Run: cellar steam restart. If it keeps happening, the log is ~/Library/Logs/Cellar/Steam.log")
}

// MARK: - Steam for Mac (or another computer) took the account: Steam says "no internet connection"

private func writeConnectionLog(_ text: String, for steam: SteamStore) throws {
    let logs = steam.steamFolder.appending(path: "logs")
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    try Data(text.utf8).write(to: logs.appending(path: "connection_log.txt"))
}

@Test func steamSignedOutElsewhereIsRestartedToSignBackIn() async throws {
    let rig = try SteamRig()
    let steam = try await rig.installedStore()
    try rig.setTasklist(["steam.exe", "steamwebhelper.exe"])
    try writeConnectionLog(SteamLogFixtures.connectionReplaced, for: steam)
    #expect(try await steam.start() == .signedBackIn)
    #expect(rig.lines(rig.calls).contains { $0.contains("-shutdown") })
    #expect(spawns(rig) == 1)
}

@Test func steamForMacStillSignedInIsNamedNotFought() async throws {
    let rig = try SteamRig()
    let steam = try await rig.installedStore(macSteam: true)
    try rig.setTasklist(["steam.exe", "steamwebhelper.exe"])
    try writeConnectionLog(SteamLogFixtures.connectionReplaced, for: steam)
    await #expect(throws: SteamError.signedInElsewhere) { try await steam.start() }
    #expect(!rig.lines(rig.calls).contains { $0.contains("-shutdown") })
    #expect(spawns(rig) == 0)
}

@Test func aSignedOutSteamIsNotRestartedUnderARunningGame() async throws {
    // A restart kills the bottle's wineserver, and the game with it (final review, 2026-10-31).
    let rig = try SteamRig()
    let steam = try await rig.installedStore()
    try rig.setTasklist(["steam.exe", "steamwebhelper.exe", "outerwilds.exe"])
    try writeConnectionLog(SteamLogFixtures.connectionReplaced, for: steam)
    await #expect(throws: SteamError.signedOutWhileGameRuns("outerwilds.exe")) { try await steam.start() }
    #expect(!rig.lines(rig.calls).contains { $0.contains("-shutdown") })
    #expect(spawns(rig) == 0)
}

@Test func signedOutWhileGameRunsSaysWhatToDo() {
    let e = SteamError.signedOutWhileGameRuns("outerwilds.exe")
    #expect(e.errorDescription == "Steam is signed out, because your account signed in somewhere else, and outerwilds.exe is still running in Steam's bottle.")
    #expect(e.recoverySuggestion == "Quit outerwilds.exe from its own menu, then run: cellar steam")
}

@Test func aMutedSteamStaysMutedWhenItSignsBackIn() async throws {
    let rig = try SteamRig()
    let steam = try await rig.installedStore()
    try rig.setTasklist(["steam.exe", "steamwebhelper.exe"])
    try writeConnectionLog(SteamLogFixtures.connectionReplaced, for: steam)
    try Data("wined3d muted".utf8).write(to: rig.tmp.paths.bottle(SteamStore.bottleName).appending(path: "steam-renderer"))
    #expect(try await steam.start() == .signedBackIn)
    #expect(steam.gamesMuted)
}

@Test func statusSaysTheAccountSignedInElsewhere() {
    let s = SteamStatus(installed: true, running: true, webhelperRunning: true, macSteamRunning: false,
                        health: SteamHealth(signIn: .signedInElsewhere(since: Date()), webhelperLaunchesLast10Min: 1,
                                            crashLoop: false, lastUpdateCheck: nil))
    let line = s.lines().first { $0.hasPrefix("Signed in:") }
    #expect(line?.contains("somewhere else") == true)
    #expect(line?.contains("cellar steam") == true)
}

@Test func signedInElsewhereErrorSaysWhatToDo() {
    #expect(SteamError.signedInElsewhere.errorDescription == "Steam is signed out, because your account signed in on Steam for Mac.")
    #expect(SteamError.signedInElsewhere.recoverySuggestion == "Quit Steam for Mac (Steam ▸ Quit Steam), then run: cellar steam")
}
