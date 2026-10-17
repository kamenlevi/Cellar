import Foundation

public enum WineRunnerError: Error, Equatable {
    /// The program didn't finish in time and was stopped (a wedged wineserver looks like this).
    case timedOut(String)
}

public struct WineResult: Sendable {
    public let exitCode: Int32
    /// Everything the program printed (stdout and stderr), up to the last 64 KB.
    public let output: String
}

/// Runs the engine's `wine` and `wineserver` for one prefix, appending everything to a log file.
public struct WineRunner: Sendable {
    public let engine: InstalledEngine
    public let prefix: URL
    public let mode: WineMode
    public let logFile: URL

    public init(engine: InstalledEngine, prefix: URL, mode: WineMode, logFile: URL) {
        self.engine = engine
        self.prefix = prefix
        self.mode = mode
        self.logFile = logFile
    }

    /// With a `timeout`, a program still running when it expires is stopped and `WineRunnerError.timedOut` thrown.
    public func wine(_ args: [String], cwd: URL? = nil, timeout: Duration? = nil) async throws -> WineResult {
        try await run(engine.wineBinary, args, cwd: cwd, timeout: timeout)
    }

    public func wineserver(_ args: [String]) async throws -> WineResult {
        try await run(engine.wineserverBinary, args, cwd: nil, timeout: nil)
    }

    /// Starts `wine args` and returns its pid at once, without waiting for it to finish.
    @discardableResult
    public func spawn(_ args: [String], cwd: URL? = nil) throws -> Int32 {
        let log = try openLog()
        try log.write(contentsOf: Data(header(engine.wineBinary, args).utf8))
        let process = makeProcess(engine.wineBinary, args, cwd: cwd, output: log)
        LiveProcesses.shared.keep(process)
        process.terminationHandler = { finished in
            try? log.close()
            LiveProcesses.shared.release(finished)
        }
        do {
            try process.run()
        } catch {
            LiveProcesses.shared.release(process)
            try? log.close()
            throw error
        }
        return process.processIdentifier
    }

    private func run(_ binary: URL, _ args: [String], cwd: URL?, timeout: Duration?) async throws -> WineResult {
        let log = try openLog()
        defer { try? log.close() }
        try log.write(contentsOf: Data(header(binary, args).utf8))
        let start = try currentSize()
        let timedOut = Flag()

        // Output goes straight to the log file rather than a pipe: wineserver lingers after wine exits
        // and would keep a pipe open.
        let process = makeProcess(binary, args, cwd: cwd, output: log)
        let code: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
            if let timeout {
                let pid = process.processIdentifier
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout.seconds) {
                    if process.isRunning {
                        timedOut.set()
                        kill(pid, SIGKILL)
                    }
                }
            }
        }
        if timedOut.isSet { throw WineRunnerError.timedOut(args.first ?? binary.lastPathComponent) }

        let reader = try FileHandle(forReadingFrom: logFile)
        defer { try? reader.close() }
        let end = try reader.seekToEnd()
        try reader.seek(toOffset: max(start, end > 65_536 ? end - 65_536 : 0))
        let output = String(decoding: try reader.readToEnd() ?? Data(), as: UTF8.self)
        return WineResult(exitCode: code, output: output)
    }

    private func makeProcess(_ binary: URL, _ args: [String], cwd: URL?, output: FileHandle) -> Process {
        let process = Process()
        process.executableURL = binary
        process.arguments = args
        process.environment = WineEnvironment.make(engine: engine, prefix: prefix, mode: mode)
        if let cwd { process.currentDirectoryURL = cwd }
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        return process
    }

    /// Append-only, so a game still writing to the bottle's log never overwrites a newer run's lines.
    private func openLog() throws -> FileHandle {
        try FileManager.default.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(logFile.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: logFile.path]) }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    private func currentSize() throws -> UInt64 {
        (try FileManager.default.attributesOfItem(atPath: logFile.path)[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private func header(_ binary: URL, _ args: [String]) -> String {
        "=== \(Date().formatted(.iso8601)) \(binary.lastPathComponent) \(args.joined(separator: " "))\n"
    }
}

/// Spawned processes stay referenced until they exit.
private final class LiveProcesses: @unchecked Sendable {
    static let shared = LiveProcesses()
    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]

    func keep(_ p: Process) { lock.withLock { processes[ObjectIdentifier(p)] = p } }
    func release(_ p: Process) { lock.withLock { processes[ObjectIdentifier(p)] = nil } }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}

extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
