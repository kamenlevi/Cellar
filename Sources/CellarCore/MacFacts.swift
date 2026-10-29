import AppKit
import CoreGraphics
import Foundation

/// What macOS itself says about a running game: its windows, whether sound is playing, which libraries it loaded.
public enum MacFacts {
    /// On-screen windows owned by `pid`, in points.
    public static func windows(pid: Int32) -> [CGRect] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { window in
            guard (window[kCGWindowOwnerPID as String] as? Int32) == pid,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: bounds)
        }
    }

    /// The main screen's size in points and its refresh rate (60 when macOS doesn't say).
    public static func screen() -> (size: CGSize, refreshRate: Double) {
        let display = CGMainDisplayID()
        let rate = NSScreen.main.map { Double($0.maximumFramesPerSecond) } ?? CGDisplayCopyDisplayMode(display)?.refreshRate ?? 0
        return (CGDisplayBounds(display).size, rate > 0 ? rate : 60)
    }

    /// Over `pmset -g assertions`: coreaudiod holds an assertion per output device while sound plays on it, named
    /// "com.apple.audio.<device>:output.context…". Newer macOS adds a "Created for PID: <pid>" line under it, which
    /// decides. Without that line the assertion counts as the game's when it is no older than `startedWithin`
    /// seconds (docs/m2-spike.md).
    public static func audioPlaying(assertions: String, pid: Int32, startedWithin: TimeInterval) -> Bool {
        let lines = assertions.split(whereSeparator: \.isNewline)
        for (i, line) in lines.enumerated() {
            guard line.contains("(coreaudiod)"), line.contains(":output.context"), let close = line.range(of: "] ") else { continue }
            let details = lines[(i + 1)...].prefix { $0.first == "\t" }
            if let owner = details.first(where: { $0.contains("Created for PID:") }) {
                if Int32(owner.split(separator: ":").last!.trimmingCharacters(in: .whitespaces.union(["."]))) == pid { return true }
                continue
            }
            let age = line[close.upperBound...].prefix { $0 != " " }.split(separator: ":").compactMap { Double($0) }
            if age.count == 3, age[0] * 3600 + age[1] * 60 + age[2] <= startedWithin { return true }
        }
        return false
    }

    /// Basenames of the files in `lsof -Fn -p <pid>` output (its "n/…" lines).
    public static func loadedLibraries(lsof: String) -> Set<String> {
        Set(lsof.split(whereSeparator: \.isNewline).compactMap { line in
            line.hasPrefix("n/") ? String(line.split(separator: "/").last ?? "") : nil
        })
    }

    /// The game's process in `ps -axo pid=,command=` output: the one whose command is the exe's path, Unix or Windows.
    public static func pid(ofExe exe: String, ps: String) -> Int32? {
        let name = exe.lowercased()
        for line in ps.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "), let pid = Int32(trimmed[..<space]) else { continue }
            let command = trimmed[space...].trimmingCharacters(in: .whitespaces).lowercased()
            if command.hasSuffix("/" + name) || command.hasSuffix("\\" + name) { return pid }
        }
        return nil
    }
}
