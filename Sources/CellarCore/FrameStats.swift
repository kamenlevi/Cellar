import Foundation

/// One Metal HUD log sample: the game's running frame count at a moment. Samples come about every 0.41 s.
public struct HUDSample: Equatable, Sendable {
    public var time: Date
    public var frameCount: Int

    public init(time: Date, frameCount: Int) {
        self.time = time
        self.frameCount = frameCount
    }
}

/// Frame rate from the Metal HUD log. The HUD's per-frame times are `<private>` in the system log, so everything here
/// comes from frame-count deltas between samples (docs/m2-spike.md): a hitch is a sample at under half the median rate.
public struct FrameStats: Equatable, Sendable {
    public var frames: Int
    public var seconds: Double
    public var averageFPS: Double
    /// The slowest ~0.4 s sample.
    public var slowestFPS: Double
    public var hitches: Int

    static let marker = "[com.apple.metal.hud:Logging] metal-HUD: "

    /// Lines as `log stream --style compact --predicate 'eventMessage CONTAINS "metal-HUD"'` writes them:
    /// "2026-10-26 20:05:47.909 Df wine[74907:26359d2] [com.apple.metal.hud:Logging] metal-HUD: 1707,565.88,…".
    /// Each sample is also logged a second time by libMTLHud.dylib; only the Logging copy counts. When several
    /// processes log, the one with the most samples is the game.
    public static func parse(hudLog: String) -> [HUDSample] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        var byProcess: [Substring: [HUDSample]] = [:]
        for line in hudLog.split(whereSeparator: \.isNewline) {
            guard line.count > 23, let marker = line.range(of: marker),
                  let time = formatter.date(from: String(line.prefix(23))),
                  let count = Int(line[marker.upperBound...].prefix { $0.isNumber }),
                  let open = line[..<marker.lowerBound].firstIndex(of: "[") else { continue }
            let pid = line[line.index(after: open)...].prefix { $0.isNumber }
            byProcess[pid, default: []].append(HUDSample(time: time, frameCount: count))
        }
        return byProcess.values.max { $0.count < $1.count } ?? []
    }

    /// Nil when there are fewer than 30 frames to go on, after dropping the first `warmup` seconds (loading screens).
    public static func summarize(_ samples: [HUDSample], skippingFirst warmup: TimeInterval = 0) -> FrameStats? {
        guard let first = samples.first else { return nil }
        let kept = samples.filter { $0.time.timeIntervalSince(first.time) >= warmup }
        var frames = 0
        var seconds = 0.0
        var rates: [Double] = []
        for (a, b) in zip(kept, kept.dropFirst()) {
            let dt = b.time.timeIntervalSince(a.time)
            let df = b.frameCount - a.frameCount
            guard dt > 0, df >= 0 else { continue }  // a smaller count means the game restarted
            frames += df
            seconds += dt
            rates.append(Double(df) / dt)
        }
        guard frames >= 30, !rates.isEmpty else { return nil }
        let median = rates.sorted()[rates.count / 2]
        return FrameStats(frames: frames, seconds: seconds, averageFPS: Double(frames) / seconds,
                          slowestFPS: rates.min()!, hitches: rates.filter { $0 < median / 2 }.count)
    }
}
