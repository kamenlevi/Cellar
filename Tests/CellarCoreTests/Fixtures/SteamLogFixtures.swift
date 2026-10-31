import Foundation

/// Steam log text in the real line formats (seen in Kamen's Steam bottles), with the account id replaced.
enum SteamLogFixtures {
    static let connectionSignedIn = """
    [2026-08-17 00:22:36] [Logged Off, 4, 0] [U:1:123456789] ConnectionDisconnected('I/O Operation Failed') : 'OK' (162.254.196.79:27019, WebSocket)
    [2026-08-17 00:22:36] [Logged Off, 4, 0] [U:1:123456789] Sending SteamServersDisconnected_t because we were logged on
    [2026-08-17 00:22:49] [Logging On, 4, 891] [U:1:123456789] RecvMsgClientLogOnResponse() : [U:1:123456789] 'OK'
    [2026-08-17 00:22:49] [Logged On, 4, 891] [U:1:123456789] RecvMsgClientLogOnResponse() : processing complete

    """

    static let connectionSignedOut = """
    [2026-08-17 00:22:49] [Logged On, 4, 891] [U:1:123456789] RecvMsgClientLogOnResponse() : processing complete
    [2026-08-17 01:10:02] [Logged Off, 4, 0] [U:1:123456789] Sending SteamServersDisconnected_t because we were logged on

    """

    /// Kamen opened Steam for Mac at 18:58 on 2026-10-30: Steam signed Cellar's Steam out and it never reconnected.
    static let connectionReplaced = """
    [2026-10-30 16:23:28] [Logged On, 4, 7] [U:1:123456789] RecvMsgClientLogOnResponse() : processing complete
    [2026-10-30 18:58:13] [Logged On, 4, 7] [U:1:123456789] RecvMsgClientLoggedOff('Session Replaced')
    [2026-10-30 18:58:13] [Logged On, 4, 7] [U:1:123456789] AsyncDisconnect( bDontWaitOnTCPShutdown: false )
    [2026-10-30 18:58:13] [Logged Off, 4, 0] [U:1:123456789] ConnectionDisconnected('Disconnected By Remote Host') : 'Session Replaced' (146.66.155.85:27018, WebSocket)
    [2026-10-30 18:58:13] [Logged Off, 4, 0] [U:1:123456789] ConnectionDisconnected() not auto reconnecting due to Session Replaced
    [2026-10-30 18:58:13] [Logged Off, 0, 0] [U:1:123456789] Sending SteamServersDisconnected_t because we were logged on
    [2026-10-30 19:23:29] CClientJobGetClientUpdateHosts: cached version not expired

    """

    /// `cellar steam restart` at 19:38 the same day: the saved login signed straight back in.
    static let connectionSignedBackIn = """
    [2026-10-30 19:38:22] [Logged Off, 4, 0] [U:1:123456789] LogOn() called; not connected yet, scheduling connection. Schedule init returned 1
    [2026-10-30 19:38:23] [Logged On, 4, 7] [U:1:123456789] RecvMsgClientLogOnResponse() : processing complete

    """

    static func webhelperLaunch(_ time: String, pid: Int) -> String {
        #"[2026-08-11 \#(time)] Startup - webhelper launched pid: \#(pid) commandline: "C:\Program Files (x86)\Steam\bin\cef\cef.win64\steamwebhelper.exe" -nocrashdialog -lang=en_US"#
    }

    static let webhelperHealthy = webhelperLaunch("16:38:17", pid: 2360) + "\n[2026-08-11 16:38:20] some other line\n"

    /// Six launches ten seconds apart: the August crash loop (216 in a row then).
    static let webhelperCrashLoop = ["16:38:10", "16:38:20", "16:38:30", "16:38:40", "16:38:50", "16:39:00"]
        .enumerated().map { webhelperLaunch($1, pid: 2000 + $0) }.joined(separator: "\n") + "\n"

    static let bootstrap = """
    [2026-08-14 01:11:23] Nothing to do
    [2026-08-14 12:13:52] Background update loop checking for update. . .
    [2026-08-14 12:13:52] Downloading manifest: https://client-update.fastly.steamstatic.com/steam_client_win64

    """

    /// Local-time date for a Steam log timestamp.
    static func local(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: s)!
    }
}
