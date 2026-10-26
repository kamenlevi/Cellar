import Foundation

public enum SignInState: Equatable, Sendable {
    case signedIn(since: Date)
    case signedOut(since: Date)
    case unknown
}

public struct SteamHealth: Equatable, Sendable {
    public var signIn: SignInState
    public var webhelperLaunchesLast10Min: Int
    /// Five or more web-helper starts in ten minutes: Steam's interface keeps crashing (the August failure).
    public var crashLoop: Bool
    public var lastUpdateCheck: Date?
}

/// Reads what Steam's own log files say. Pure functions: text in, facts out.
public enum SteamLogs {
    static let crashLoopThreshold = 5

    /// Steam log lines start with a local-time stamp: "[2026-08-17 00:22:49] …"
    static func timestamp(_ line: Substring) -> Date? {
        guard line.count >= 21, line.first == "[" else { return nil }
        let start = line.index(after: line.startIndex)
        let end = line.index(start, offsetBy: 19)
        guard line[end] == "]" else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: String(line[start..<end]))
    }

    public static func signIn(connectionLog: String) -> SignInState {
        for line in connectionLog.split(whereSeparator: \.isNewline).reversed() {
            guard let time = timestamp(line) else { continue }
            if line.contains("[Logged On,") { return .signedIn(since: time) }
            if line.contains("[Logged Off,") { return .signedOut(since: time) }
        }
        return .unknown
    }

    public static func webhelperLaunches(webhelperLog: String, since: Date) -> Int {
        webhelperLog.split(whereSeparator: \.isNewline).count { line in
            guard line.contains("Startup - webhelper launched pid:"), let time = timestamp(line) else { return false }
            return time >= since
        }
    }

    public static func lastUpdateCheck(bootstrapLog: String) -> Date? {
        for line in bootstrapLog.split(whereSeparator: \.isNewline).reversed()
        where line.contains("checking for update") || line.contains("Nothing to do") {
            if let time = timestamp(line) { return time }
        }
        return nil
    }

    public static func health(connectionLog: String, webhelperLog: String, bootstrapLog: String, now: Date) -> SteamHealth {
        let launches = webhelperLaunches(webhelperLog: webhelperLog, since: now.addingTimeInterval(-600))
        return SteamHealth(signIn: signIn(connectionLog: connectionLog),
                           webhelperLaunchesLast10Min: launches,
                           crashLoop: launches >= crashLoopThreshold,
                           lastUpdateCheck: lastUpdateCheck(bootstrapLog: bootstrapLog))
    }

    /// "[U:1:123456789]" → "[U:1:…]": Steam account ids never leave the log files.
    public static func redactAccountIds(_ text: String) -> String {
        text.replacing(/\[U:1:\d+\]/, with: "[U:1:…]")
    }
}
