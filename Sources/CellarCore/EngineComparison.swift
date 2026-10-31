import Foundation

/// One way a game ran worse on a candidate engine than on the baseline engine.
public struct ComparisonFinding: Equatable, Sendable {
    public var game: String
    public var what: String
    public var baseline: String
    public var candidate: String
}

/// Judges a candidate engine's checks of one game against the baseline engine's (M4: nothing may get worse).
public enum EngineComparison {
    /// Empty when nothing is worse. Baseline runs are at least two, so their spread is measured, not guessed; the spread
    /// is capped at 5 % of the lowest baseline average, so one noisy run can't excuse a slow candidate.
    public static func verdict(baseline: [CheckReport], candidate: [CheckReport]) -> [ComparisonFinding] {
        guard let game = (candidate.first ?? baseline.first)?.game.name else { return [] }
        var findings: [ComparisonFinding] = []
        func add(_ what: String, _ base: String, _ cand: String) {
            findings.append(ComparisonFinding(game: game, what: what, baseline: base, candidate: cand))
        }

        for (what, value) in [("renderer", \CheckReport.rendererLoaded), ("still running", \.stillRunning),
                              ("window", \.windowFillsScreen)] as [(String, KeyPath<CheckReport, Bool?>)]
        where baseline.allSatisfy({ $0[keyPath: value] == true }) && candidate.contains(where: { $0[keyPath: value] != true }) {
            add(what, "yes in every run", "no")
        }

        let baseFrames = baseline.compactMap(\.frames), candFrames = candidate.compactMap(\.frames)
        if !baseFrames.isEmpty && candFrames.count < candidate.count {
            add("frame data", "measured", "missing")
        }
        if let low = baseFrames.map(\.averageFPS).min(), let high = baseFrames.map(\.averageFPS).max(),
           let lowSlowest = baseFrames.map(\.slowestFPS).min(), let mostHitches = baseFrames.map(\.hitches).max() {
            let spread = min(high - low, low * 0.05)
            if let worst = candFrames.map(\.averageFPS).min(), worst < low - spread {
                add("frame rate", "\(fps(low))–\(fps(high)) fps", "\(fps(worst)) fps")
            }
            if let worst = candFrames.map(\.slowestFPS).min(), worst < lowSlowest - spread {
                add("slowest moment", "\(fps(lowSlowest)) fps", "\(fps(worst)) fps")
            }
            if let most = candFrames.map(\.hitches).max(), most > mostHitches + 1 {
                add("hitches", "\(mostHitches)", "\(most)")
            }
        }

        let known = Set(baseline.flatMap(\.wineErrors).map(errorKind))
        let new = Set(candidate.flatMap(\.wineErrors).map(errorKind)).subtracting(known).sorted()
        if !new.isEmpty { add("Wine errors", "\(known.count) kinds", "new: " + new.joined(separator: ", ")) }
        return findings
    }

    /// "err:d3d11:d3d11_device_CreateTexture2D failed" → "err:d3d11:d3d11_device_CreateTexture2D".
    static func errorKind(_ line: String) -> String {
        String(line.split(separator: " ", maxSplits: 1).first ?? Substring(line))
    }

    private static func fps(_ value: Double) -> String { String(format: "%.1f", value) }
}
