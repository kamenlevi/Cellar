import CoreGraphics
import Foundation

/// The automatic part of the spec's per-game checklist (section 4), measured on a real run.
public struct CheckReport: Sendable {
    public var game: GameProfile
    public var renderer: Renderer
    public var seconds: Int
    public var startedAt: Date
    /// False when the game was already running: it then has no HUD, so there is no frame data.
    public var launched: Bool
    public var refreshRate: Double
    public var frames: FrameStats?
    public var windowFillsScreen: Bool?
    public var audio: Bool?
    public var rendererLoaded: Bool?
    public var stillRunning: Bool?
    public var wineErrors: [String]
    /// Nil when the profile names no save folder.
    public var savesChanged: Bool?

    /// What the game must hold: 95% of the display's refresh rate (or of the game's own rate when that is lower), and at
    /// most one hitch per minute.
    var targetFPS: Double { min(refreshRate, game.fps.map(Double.init) ?? refreshRate) * 0.95 }
    var allowedHitches: Int { max(1, seconds / 60) }

    /// Failures in the checklist's order; empty when the automatic part passes.
    var failures: [String] {
        var out: [String] = []
        if stillRunning != true { out.append("the game quit or crashed during the check") }
        if rendererLoaded != true { out.append("\(renderer.displayName) isn't loaded in the game") }
        if windowFillsScreen != true { out.append("the window doesn't fill the screen") }
        if audio != true { out.append("no sound started playing") }
        if let frames {
            if frames.averageFPS < targetFPS { out.append("\(Int(frames.averageFPS.rounded())) fps, under \(Int(targetFPS.rounded()))") }
            if frames.hitches > allowedHitches { out.append("\(frames.hitches) hitches, more than \(allowedHitches)") }
        } else {
            out.append("no frame data")
        }
        return out
    }

    public var automaticVerdict: String {
        failures.first.map { "FAIL: \($0)" } ?? "PASS (automatic part)"
    }

    public func markdown() -> String {
        func mark(_ value: Bool?) -> String { value.map { $0 ? "yes" : "**no**" } ?? "not measured" }
        var lines = [
            "# \(game.name): check",
            "",
            "\(startedAt.formatted(date: .abbreviated, time: .shortened)), \(seconds) s, \(renderer.displayName). "
                + "**\(automaticVerdict)**",
            "",
            "## Automatic",
            "",
            "- Launches and keeps running: \(mark(stillRunning))\(launched ? "" : " (it was already running)")",
            "- Renderer loaded: \(mark(rendererLoaded))",
            "- Window fills the screen: \(mark(windowFillsScreen))",
            "- Sound playing: \(mark(audio))",
        ]
        if let frames {
            lines.append("- Frame rate: \(String(format: "%.1f", frames.averageFPS)) fps average over \(Int(frames.seconds)) s "
                         + "(target \(Int(targetFPS.rounded())), display \(Int(refreshRate)) Hz); slowest moment "
                         + "\(String(format: "%.0f", frames.slowestFPS)) fps; \(frames.hitches) hitches (allowed \(allowedHitches))")
        } else {
            lines.append("- Frame rate: no frame data" + (launched ? "" : " (quit the game and run the check again)"))
        }
        lines.append("- Saves written during the check: " + (savesChanged.map { $0 ? "yes" : "no" } ?? "no save folder known"))
        lines += ["", "## Wine errors", ""]
        lines += wineErrors.isEmpty ? ["None."] : wineErrors.map { "    \($0)" }
        lines += ["", "## Kamen checks", ""]
        lines += ["reaches gameplay", "visuals match reference footage", "music and sound effects, no crackle",
                  "cutscenes and video", "keyboard and mouse", "DualSense, rumble included", "saves persist, Steam Cloud syncs",
                  "quit and relaunch is clean"].map { "- [ ] \($0)" }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Writes the report as "<game>-<date>.md" in `folder` and returns its path.
    public func write(to folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let file = folder.appending(path: "\(game.id)-\(formatter.string(from: startedAt)).md")
        try Data(markdown().utf8).write(to: file)
        return file
    }
}

/// How a check reads the Mac. Live by default; tests pass their own.
public struct MacProbe: Sendable {
    /// Starts capturing the Metal HUD log into a file; returns what stops it.
    public var hudLog: @Sendable (URL) throws -> @Sendable () -> Void
    public var windows: @Sendable (Int32) -> [CGRect]
    public var screen: @Sendable () -> (size: CGSize, refreshRate: Double)
    public var assertions: @Sendable () -> String
    public var lsof: @Sendable (Int32) -> String
    public var ps: @Sendable () -> String

    public static let live = MacProbe(
        hudLog: { file in
            FileManager.default.createFile(atPath: file.path, contents: nil)
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/log")
            process.arguments = ["stream", "--style", "compact", "--predicate", #"eventMessage CONTAINS "metal-HUD""#]
            let handle = try FileHandle(forWritingTo: file)
            process.standardOutput = handle
            process.standardError = FileHandle.nullDevice
            try process.run()
            return { process.terminate(); process.waitUntilExit(); try? handle.close() }
        },
        windows: MacFacts.windows(pid:),
        screen: MacFacts.screen,
        assertions: { output("/usr/bin/pmset", ["-g", "assertions"]) },
        lsof: { output("/usr/sbin/lsof", ["-Fn", "-p", String($0)]) },
        ps: { output("/bin/ps", ["-axo", "pid=,command="]) })

    private static func output(_ tool: String, _ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

/// Starts a game with the Metal HUD logging, watches it for a while and reports. It never quits the game.
public struct GameCheck: Sendable {
    let paths: CellarPaths
    let games: GameStore
    let steam: SteamStore
    let probe: MacProbe
    let warmup: TimeInterval

    public init(paths: CellarPaths, games: GameStore, steam: SteamStore, probe: MacProbe = .live, warmup: TimeInterval = 20) {
        self.paths = paths
        self.games = games
        self.steam = steam
        self.probe = probe
        self.warmup = warmup
    }

    public var reportFolder: URL { paths.logs.appending(path: "checks", directoryHint: .isDirectory) }

    public func run(_ profile: GameProfile, seconds: Int) async throws -> CheckReport {
        let startedAt = Date()
        let runner = try steam.bottles.runner(for: steam.name, mode: .interactive)
        let logStart = (try? FileManager.default.attributesOfItem(atPath: runner.logFile.path)[.size] as? NSNumber)?.uint64Value ?? 0
        let saves = profile.saves.map {
            runner.prefix.appending(path: "drive_c/users/\(NSUserName())/\($0)", directoryHint: .isDirectory)
        }
        let savesBefore = saves.map(Self.newestChange)

        try FileManager.default.createDirectory(at: reportFolder, withIntermediateDirectories: true)
        let hudFile = reportFolder.appending(path: "\(profile.id)-hud.log")
        let stopHUD = try probe.hudLog(hudFile)
        let outcome: PlayOutcome
        do {
            outcome = try await games.play(profile, extraEnvironment: [
                "MTL_HUD_ENABLED": "1", "MTL_HUD_LOG_ENABLED": "1", "WINEDEBUG": "fixme-all,err+all",
            ])
        } catch {
            stopHUD()
            throw error
        }

        let midway = min(30, seconds)
        try await Task.sleep(for: .seconds(midway))
        let early = sample(profile, since: startedAt)
        try await Task.sleep(for: .seconds(seconds - midway))
        let late = sample(profile, since: startedAt)
        stopHUD()

        let launched = if case .launched = outcome { true } else { false }
        let hud = (try? String(contentsOf: hudFile, encoding: .utf8)) ?? ""
        let samples = FrameStats.parse(hudLog: hud)
        let log = Self.read(runner.logFile, from: logStart)
        let savesAfter = saves.map(Self.newestChange)

        return CheckReport(
            game: profile, renderer: profile.renderer, seconds: seconds, startedAt: startedAt, launched: launched,
            refreshRate: probe.screen().refreshRate,
            frames: FrameStats.summarize(samples, skippingFirst: launched ? warmup : 0, target: profile.fps.map(Double.init)),
            windowFillsScreen: late.pid != nil ? late.fillsScreen : early.fillsScreen,
            audio: early.audio || late.audio,
            rendererLoaded: early.libraries.union(late.libraries).contains(Self.marker(profile.renderer)),
            stillRunning: late.pid != nil,
            wineErrors: Self.wineErrors(log: log),
            savesChanged: savesAfter.flatMap { after in savesBefore.map { after > $0 } })
    }

    private struct Sample {
        var pid: Int32?
        var fillsScreen = false
        var audio = false
        var libraries: Set<String> = []
    }

    private func sample(_ profile: GameProfile, since start: Date) -> Sample {
        let exe = (profile.exe as NSString).lastPathComponent
        guard let pid = MacFacts.pid(ofExe: exe, ps: probe.ps()) else { return Sample() }
        let screen = probe.screen().size
        let fills = probe.windows(pid).contains { $0.width >= screen.width * 0.98 && $0.height >= screen.height * 0.98 }
        return Sample(pid: pid, fillsScreen: fills,
                      audio: MacFacts.audioPlaying(assertions: probe.assertions(), startedWithin: Date().timeIntervalSince(start) + 2),
                      libraries: MacFacts.loadedLibraries(lsof: probe.lsof(pid)))
    }

    /// The library whose presence shows the renderer is in use.
    static func marker(_ renderer: Renderer) -> String {
        switch renderer {
        case .d3dmetal: "D3DMetal"
        case .dxvk: "libMoltenVK.dylib"
        case .wined3d: "wined3d.dll"
        }
    }

    /// Wine's "err:" lines, without the thread id in front, each once, the first 20.
    static func wineErrors(log: String) -> [String] {
        var seen: Set<Substring> = []
        var out: [String] = []
        for line in log.split(whereSeparator: \.isNewline) {
            guard let err = line.range(of: "err:") else { continue }
            let message = line[err.lowerBound...]
            if seen.insert(message).inserted { out.append(String(message)) }
            if out.count == 20 { break }
        }
        return out
    }

    private static func read(_ file: URL, from offset: UInt64) -> String {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return "" }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        return String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
    }

    /// The newest modification time of anything in a folder (distantPast when it is empty or missing).
    private static func newestChange(_ folder: URL) -> Date {
        let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
        var newest = Date.distantPast
        while let item = items?.nextObject() as? URL {
            if let date = try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date > newest {
                newest = date
            }
        }
        return newest
    }
}
