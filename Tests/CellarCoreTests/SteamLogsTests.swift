import Foundation
import Testing
@testable import CellarCore

private typealias F = SteamLogFixtures

@Test func signedInWhenLastStateIsLoggedOn() {
    #expect(SteamLogs.signIn(connectionLog: F.connectionSignedIn) == .signedIn(since: F.local("2026-08-17 00:22:49")))
}

@Test func signedOutWhenLastStateIsLoggedOff() {
    #expect(SteamLogs.signIn(connectionLog: F.connectionSignedOut) == .signedOut(since: F.local("2026-08-17 01:10:02")))
}

@Test func unknownWhenNoStateLines() {
    #expect(SteamLogs.signIn(connectionLog: "") == .unknown)
}

@Test func signedOutBecauseTheAccountSignedInElsewhere() {
    #expect(SteamLogs.signIn(connectionLog: F.connectionReplaced) == .signedInElsewhere(since: F.local("2026-10-30 18:58:13")))
}

@Test func signingBackInAfterAReplacementIsSignedIn() {
    #expect(SteamLogs.signIn(connectionLog: F.connectionReplaced + F.connectionSignedBackIn)
            == .signedIn(since: F.local("2026-10-30 19:38:23")))
}

@Test func aSteamStillSigningInAfterAReplacementIsSignedOutNotElsewhere() {
    // Restarted after the replacement, Steam logs "LogOn() called" (as Logged Off) until it connects; that is a new
    // attempt, not the replaced session (final review, 2026-10-31).
    let log = F.connectionReplaced + "[2026-10-30 19:38:22] [Logged Off, 4, 0] [U:1:123456789] LogOn() called; not connected yet, scheduling connection. Schedule init returned 1\n"
    #expect(SteamLogs.signIn(connectionLog: log) == .signedOut(since: F.local("2026-10-30 19:38:22")))
}

@Test func anOldReplacementDoesNotExplainALaterSignOut() {
    let later = "[2026-10-30 20:00:00] [Logged Off, 4, 0] [U:1:123456789] Sending SteamServersDisconnected_t because we were logged on\n"
    #expect(SteamLogs.signIn(connectionLog: F.connectionReplaced + F.connectionSignedBackIn + later)
            == .signedOut(since: F.local("2026-10-30 20:00:00")))
}

@Test func healthyWebhelperIsNotALoop() {
    let h = SteamLogs.health(connectionLog: "", webhelperLog: F.webhelperHealthy, bootstrapLog: "",
                             now: F.local("2026-08-11 16:40:00"))
    #expect(h.webhelperLaunchesLast10Min == 1)
    #expect(!h.crashLoop)
}

@Test func sixLaunchesInAMinuteIsTheAugustCrashLoop() {
    let h = SteamLogs.health(connectionLog: "", webhelperLog: F.webhelperCrashLoop, bootstrapLog: "",
                             now: F.local("2026-08-11 16:39:30"))
    #expect(h.webhelperLaunchesLast10Min == 6)
    #expect(h.crashLoop)
}

@Test func oldLaunchesDoNotCount() {
    let h = SteamLogs.health(connectionLog: "", webhelperLog: F.webhelperCrashLoop, bootstrapLog: "",
                             now: F.local("2026-08-11 16:50:01"))
    #expect(h.webhelperLaunchesLast10Min == 0)
    #expect(!h.crashLoop)
}

@Test func lastUpdateCheckIsRead() {
    #expect(SteamLogs.lastUpdateCheck(bootstrapLog: F.bootstrap) == F.local("2026-08-14 12:13:52"))
}

@Test func accountIdsAreRedacted() {
    #expect(SteamLogs.redactAccountIds("x [U:1:123456789] y") == "x [U:1:…] y")
    #expect(!SteamLogs.redactAccountIds(F.connectionSignedIn).contains("123456789"))
}

@Test func garbageLinesAreIgnored() {
    #expect(SteamLogs.signIn(connectionLog: "\u{0}\n[not a date] [Logged On, 4]\n") == .unknown)
    #expect(SteamLogs.webhelperLaunches(webhelperLog: "Startup - webhelper launched pid: 1\n", since: .distantPast) == 0)
}

// Windows writes "\r\n". Swift treats "\r\n" as one Character, so splitting on "\n" finds nothing.
private func crlf(_ s: String) -> String { s.replacingOccurrences(of: "\n", with: "\r\n") }

@Test func windowsLineEndingsAreRead() {
    #expect(SteamLogs.signIn(connectionLog: crlf(F.connectionSignedIn)) == .signedIn(since: F.local("2026-08-17 00:22:49")))
    #expect(SteamLogs.lastUpdateCheck(bootstrapLog: crlf(F.bootstrap)) == F.local("2026-08-14 12:13:52"))
    #expect(SteamLogs.webhelperLaunches(webhelperLog: crlf(F.webhelperCrashLoop), since: .distantPast) == 6)
}

// Steam's console log, 2026-10-30: Outer Wilds waited on a notice; Chants of Sennaar started.
private let launches = """
[2026-10-30 20:21:44] GameAction [AppID 1931770, ActionID 2] : LaunchApp changed task to WaitingGameWindow with ""
[2026-10-30 20:21:44] GameAction [AppID 1931770, ActionID 2] : LaunchApp changed task to Completed with ""
[2026-10-30 20:29:41] GameAction [AppID 753640, ActionID 2] : LaunchApp changed task to ShowInterstitials with ""
[2026-10-30 20:29:41] GameAction [AppID 753640, ActionID 2] : LaunchApp waiting for user response to ShowInterstitials ""

"""

@Test func aLaunchWaitingOnANoticeIsSeen() {
    #expect(SteamLogs.launchWaitingForYou(consoleLog: crlf(launches), appid: 753640, since: F.local("2026-10-30 20:29:00")))
}

@Test func aLaunchThatWentAheadIsNotWaiting() {
    #expect(!SteamLogs.launchWaitingForYou(consoleLog: launches, appid: 1931770, since: F.local("2026-10-30 20:21:00")))
}

@Test func aNoticeFromBeforeTheAskDoesNotCount() {
    #expect(!SteamLogs.launchWaitingForYou(consoleLog: launches, appid: 753640, since: F.local("2026-10-30 20:30:00")))
}
