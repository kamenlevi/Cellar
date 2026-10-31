import CoreGraphics
import Foundation
import Testing
@testable import CellarCore

private let outerWilds = GameProfile(id: "outer-wilds", name: "Outer Wilds", appid: 753640, exe: "OuterWilds.exe",
                                     renderer: .d3dmetal, saves: nil, launch: .direct)

private func report(frames: FrameStats? = FrameStats(frames: 14_400, seconds: 120, averageFPS: 120, slowestFPS: 110, hitches: 0),
                    window: Bool? = true, audio: Bool? = true, renderer: Bool? = true, running: Bool? = true) -> CheckReport {
    CheckReport(game: outerWilds, renderer: .d3dmetal, seconds: 120, startedAt: Date(timeIntervalSince1970: 0), launched: true,
                refreshRate: 120, frames: frames, windowFillsScreen: window, audio: audio, rendererLoaded: renderer,
                stillRunning: running, wineErrors: [], savesChanged: nil)
}

@Test func reportSaysNoFrameDataInsteadOfZero() {
    let text = report(frames: nil).markdown()
    #expect(text.contains("no frame data"))
    #expect(!text.contains("0.0 fps"))
}

@Test func verdictNamesTheFirstFailure() {
    #expect(report().automaticVerdict == "PASS (automatic part)")
    #expect(report(audio: false, running: false).automaticVerdict.hasPrefix("FAIL: the game quit"))
    #expect(report(window: false, audio: false).automaticVerdict.hasPrefix("FAIL: the window"))
    #expect(report(frames: nil).automaticVerdict == "FAIL: no frame data")
    let slow = FrameStats(frames: 9000, seconds: 120, averageFPS: 75, slowestFPS: 60, hitches: 0)
    #expect(report(frames: slow).automaticVerdict.hasPrefix("FAIL: 75 fps"))
    let stuttery = FrameStats(frames: 14_000, seconds: 120, averageFPS: 117, slowestFPS: 20, hitches: 5)
    #expect(report(frames: stuttery).automaticVerdict.hasPrefix("FAIL: 5 hitches"))
}

@Test func wineErrorsAreDedupedWithoutThreadIds() {
    let log = """
    === 2026-10-29T13:35:00Z wine RainWorld.exe
    0520:err:vulkan:init_vulkan Failed to load Wine graphics driver supporting Vulkan.
    0524:err:vulkan:init_vulkan Failed to load Wine graphics driver supporting Vulkan.
    info:  Game: RainWorld.exe
    0530:err:secur32:SECUR32_initSchannelSP no schannel support, expect problems
    """
    #expect(GameCheck.wineErrors(log: log) == [
        "err:vulkan:init_vulkan Failed to load Wine graphics driver supporting Vulkan.",
        "err:secur32:SECUR32_initSchannelSP no schannel support, expect problems",
    ])
}

@Test func checkStartsTheGameWithTheHUDAndReadsItsFacts() async throws {
    let rig = try await GameRig()
    let exe = rig.steam.steamFolder.appending(path: "steamapps/common/Outer Wilds/OuterWilds.exe").path
    let probe = MacProbe(
        hudLog: { file in
            try Data(HUDLogFixtures.d3dmetal.utf8).write(to: file)
            return {}
        },
        windows: { pid in pid == 4242 ? [CGRect(x: 0, y: 0, width: 1512, height: 982)] : [] },
        screen: { (CGSize(width: 1512, height: 982), 120) },
        assertions: { pmsetWhilePlaying.replacingOccurrences(of: "00:00:43", with: "00:00:01") },
        lsof: { pid in pid == 4242 ? "p4242\nftxt\nn/x/D3DMetal.framework/Versions/A/D3DMetal\n" : "" },
        ps: { "  4242 \(exe) \n" })
    let check = GameCheck(paths: rig.tmp.paths, games: rig.games, steam: rig.steam, probe: probe, warmup: 10)
    let result = try await check.run(outerWilds, seconds: 1)
    #expect(result.launched)
    #expect(abs((result.frames?.averageFPS ?? 0) - 120) < 0.5)
    #expect(result.automaticVerdict == "PASS (automatic part)")
    let line = try #require(await rig.waitFor("OuterWilds.exe"))
    #expect(line.contains("appid=753640"))

    let saved = try result.write(to: rig.tmp.url.appending(path: "checks"))
    #expect(try String(contentsOf: saved, encoding: .utf8).contains("PASS (automatic part)"))
}

@Test func aGameThatNeedsLessThanTheDisplayIsHeldToItsOwnRate() {
    var check = report(frames: FrameStats(frames: 11_640, seconds: 120, averageFPS: 97, slowestFPS: 9, hitches: 1))
    #expect(check.automaticVerdict.hasPrefix("FAIL: 97 fps, under 114"))
    check.game.fps = 60
    #expect(check.automaticVerdict == "PASS (automatic part)")
    #expect(check.markdown().contains("target 57"))
}

@Test func mutedCheckDoesNotJudgeSound() {
    var check = report(audio: nil)
    #expect(check.automaticVerdict.hasPrefix("FAIL: no sound"))
    check.muted = true
    #expect(check.automaticVerdict == "PASS (automatic part)")
    #expect(check.markdown().contains("muted"))
}

@Test func aWrittenReportHasItsJSONBesideIt() throws {
    // M4's engine comparison reads these.
    let tmp = try TempRoot()
    let md = try report().write(to: tmp.url)
    let json = md.deletingPathExtension().appendingPathExtension("json")
    #expect(try JSONDecoder.cellar.decode(CheckReport.self, from: Data(contentsOf: json)) == report())
}
