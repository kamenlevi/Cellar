import Foundation
import Testing
@testable import CellarCore

/// HUD samples every `step` seconds, each adding the given number of frames to the running count.
private func samples(_ framesPerSample: [Int], every step: Double = 0.4) -> [HUDSample] {
    var count = 0
    var out = [HUDSample(time: Date(timeIntervalSince1970: 0), frameCount: 0)]
    for (i, frames) in framesPerSample.enumerated() {
        count += frames
        out.append(HUDSample(time: Date(timeIntervalSince1970: Double(i + 1) * step), frameCount: count))
    }
    return out
}

@Test func parsesRealHUDLines() throws {
    let parsed = FrameStats.parse(hudLog: HUDLogFixtures.d3dmetal)
    #expect(parsed.count == 21)  // every sample once, though the log has the first one twice
    #expect(parsed.first?.frameCount == 53)
    #expect(parsed.last?.frameCount == 2638)
    let stats = try #require(FrameStats.summarize(parsed, skippingFirst: 10))
    #expect(stats.frames == 2638 - 1707)
    #expect(abs(stats.averageFPS - 120) < 0.5)
    #expect(stats.hitches == 0)
}

@Test func realDXVKLinesAre120() throws {
    let stats = try #require(FrameStats.summarize(FrameStats.parse(hudLog: HUDLogFixtures.dxvk)))
    #expect(abs(stats.averageFPS - 120) < 0.5)
}

@Test func steady60fps() throws {
    let stats = try #require(FrameStats.summarize(samples(Array(repeating: 24, count: 150))))
    #expect(stats.frames == 3600)
    #expect(abs(stats.averageFPS - 60) < 0.01)
    #expect(abs(stats.slowestFPS - 60) < 0.01)
    #expect(stats.hitches == 0)
}

@Test func oneHitchIsCounted() throws {
    var frames = Array(repeating: 48, count: 50)
    frames[25] = 4
    let stats = try #require(FrameStats.summarize(samples(frames)))
    #expect(stats.hitches == 1)
    #expect(abs(stats.slowestFPS - 10) < 0.01)
}

@Test func tooFewFramesIsNoData() {
    #expect(FrameStats.summarize(samples([10, 10])) == nil)
    #expect(FrameStats.summarize(samples([])) == nil)
    #expect(FrameStats.summarize(samples(Array(repeating: 48, count: 50)), skippingFirst: 60) == nil)
}

@Test func onlyTheBusiestProcessCounts() {
    let log = """
    2026-10-29 15:35:30.505 Df wine[81300:28c83ec] [com.apple.metal.hud:Logging] metal-HUD: 5671,619.25,2046.06<private>
    2026-10-29 15:35:30.600 Df wine[90000:28c83ec] [com.apple.metal.hud:Logging] metal-HUD: 7,1.0,2.0<private>
    2026-10-29 15:35:30.913 Df wine[81300:28c82f5] (libMTLHud.dylib) metal-HUD: 5720,619.25,2046.06<private>
    2026-10-29 15:35:30.913 Df wine[81300:28c82f5] [com.apple.metal.hud:Logging] metal-HUD: 5720,619.25,2046.06<private>
    """
    #expect(FrameStats.parse(hudLog: log).map(\.frameCount) == [5671, 5720])
}

@Test func counterRestartIsNotNegativeFrames() throws {
    var parsed = samples(Array(repeating: 48, count: 40))
    parsed.append(HUDSample(time: Date(timeIntervalSince1970: 16.4), frameCount: 10))  // the game restarted
    let stats = try #require(FrameStats.summarize(parsed))
    #expect(stats.frames == 40 * 48)
}
