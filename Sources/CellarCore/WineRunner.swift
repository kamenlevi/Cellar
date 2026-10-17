import Foundation

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

    public func wine(_ args: [String], cwd: URL? = nil) async throws -> WineResult {
        try await run(engine.wineBinary, args, cwd: cwd)
    }

    public func wineserver(_ args: [String]) async throws -> WineResult {
        try await run(engine.wineserverBinary, args, cwd: nil)
    }

    private func run(_ binary: URL, _ args: [String], cwd: URL?) async throws -> WineResult {
        let fm = FileManager.default
        try fm.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: logFile.path) { fm.createFile(atPath: logFile.path, contents: nil) }

        let log = try FileHandle(forWritingTo: logFile)
        defer { try? log.close() }
        try log.seekToEnd()
        let header = "=== \(Date().formatted(.iso8601)) \(binary.lastPathComponent) \(args.joined(separator: " "))\n"
        try log.write(contentsOf: Data(header.utf8))
        let start = try log.offset()

        // Output goes straight to the log file rather than a pipe: wineserver lingers after wine exits
        // and would keep a pipe open.
        let process = Process()
        process.executableURL = binary
        process.arguments = args
        process.environment = WineEnvironment.make(engine: engine, prefix: prefix, mode: mode)
        if let cwd { process.currentDirectoryURL = cwd }
        process.standardOutput = log
        process.standardError = log
        process.standardInput = FileHandle.nullDevice

        let code: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }

        let reader = try FileHandle(forReadingFrom: logFile)
        defer { try? reader.close() }
        let end = try reader.seekToEnd()
        try reader.seek(toOffset: max(start, end > 65_536 ? end - 65_536 : 0))
        let output = String(decoding: try reader.readToEnd() ?? Data(), as: UTF8.self)
        return WineResult(exitCode: code, output: output)
    }
}
