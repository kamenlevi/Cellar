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
