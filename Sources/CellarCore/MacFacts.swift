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
    /// "com.apple.audio.<device>:output.context…", and it names the device, never the program (docs/m2-spike.md). So
    /// sound counts as the game's when such an assertion is no older than `startedWithin` seconds.
    public static func audioPlaying(assertions: String, startedWithin: TimeInterval) -> Bool {
        assertions.split(whereSeparator: \.isNewline).contains { line in
            guard line.contains("(coreaudiod)"), line.contains(":output.context"),
                  let close = line.range(of: "] ") else { return false }
            let age = line[close.upperBound...].prefix { $0 != " " }.split(separator: ":").compactMap { Double($0) }
            guard age.count == 3 else { return false }
            return age[0] * 3600 + age[1] * 60 + age[2] <= startedWithin
        }
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
