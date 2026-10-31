import Foundation
import Testing
@testable import CellarCore

private let chants = GameProfile(id: "chants-of-sennaar", name: "Chants of Sennaar", appid: 1931770,
                                 exe: "Chants Of Sennaar.exe", renderer: .d3dmetal)

private func run(_ fps: Double, slowest: Double? = nil, hitches: Int = 0, renderer: Bool = true,
                 errors: [String] = []) -> CheckReport {
    CheckReport(game: chants, renderer: .d3dmetal, seconds: 120, startedAt: Date(timeIntervalSince1970: 0), launched: true,
                refreshRate: 120,
                frames: FrameStats(frames: Int(fps * 120), seconds: 120, averageFPS: fps, slowestFPS: slowest ?? fps - 10, hitches: hitches),
                windowFillsScreen: true, audio: nil, rendererLoaded: renderer, stillRunning: true, wineErrors: errors,
                savesChanged: nil, muted: true)
}

@Test func anEqualCandidateIsNotWorse() {
    #expect(EngineComparison.verdict(baseline: [run(118), run(120)], candidate: [run(119)]) == [])
}

@Test func aSlowerCandidateBeyondTheSpreadIsWorse() {
    let findings = EngineComparison.verdict(baseline: [run(118), run(120)], candidate: [run(115, slowest: 108)])
    #expect(findings.map(\.what) == ["frame rate"])
}

@Test func aCandidateWithoutItsRendererFailsWhateverItsFrameRate() {
    let findings = EngineComparison.verdict(baseline: [run(118), run(120)], candidate: [run(200, renderer: false)])
    #expect(findings.map(\.what) == ["renderer"])
}

@Test func aHugeBaselineSpreadIsCapped() {
    // 60 and 120: the spread would be 60, but it is capped at 5 % of the lowest (3), so 50 is worse.
    let findings = EngineComparison.verdict(baseline: [run(60, slowest: 40), run(120, slowest: 40)], candidate: [run(50, slowest: 40)])
    #expect(findings.map(\.what) == ["frame rate"])
}

@Test func aNewKindOfWineErrorIsReported() {
    let base = ["err:mmdevapi:init_driver No driver from L\"coreaudio\" could be initialized."]
    let findings = EngineComparison.verdict(baseline: [run(118, errors: base), run(120, errors: base)],
                                            candidate: [run(119, errors: base + ["err:d3d11:d3d11_device_CreateTexture2D failed"])])
    #expect(findings.map(\.what) == ["Wine errors"])
    #expect(findings.first?.candidate.contains("err:d3d11:d3d11_device_CreateTexture2D") == true)
}

@Test func reportsRoundTripThroughJSON() throws {
    let original = run(119, errors: ["err:x:y z"])
    let decoded = try JSONDecoder().decode(CheckReport.self, from: try JSONEncoder().encode(original))
    #expect(decoded == original)
}
