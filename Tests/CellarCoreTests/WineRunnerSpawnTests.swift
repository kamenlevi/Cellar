import Foundation
import Testing
@testable import CellarCore

private func waitFor(_ timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(100))
    }
    return condition()
}

@Test func spawnReturnsBeforeTheProgramEnds() async throws {
    let tmp = try TempRoot()
    let marker = tmp.url.appending(path: "done.txt")
    let engine = try FakeEngine.installed(in: tmp.url, wine: "#!/bin/sh\nsleep 2\necho done >> '\(marker.path)'\n")
    let runner = WineRunner(engine: engine, prefix: tmp.url.appending(path: "p"), mode: .headless,
                            logFile: tmp.url.appending(path: "l.log"))
    let t0 = Date()
    let pid = try runner.spawn(["steam.exe"])
    #expect(Date().timeIntervalSince(t0) < 1)
    #expect(pid > 0)
    #expect(!FileManager.default.fileExists(atPath: marker.path))
    #expect(await waitFor(6) { FileManager.default.fileExists(atPath: marker.path) })
}

@Test func concurrentWritersDoNotOverwriteEachOther() async throws {
    let tmp = try TempRoot()
    let engine = try FakeEngine.installed(in: tmp.url,
        wine: "#!/bin/sh\nfor i in 1 2 3 4 5; do echo \"$1-$i\"; sleep 0.05; done\n")
    let log = tmp.url.appending(path: "l.log")
    let runner = WineRunner(engine: engine, prefix: tmp.url.appending(path: "p"), mode: .headless, logFile: log)
    _ = try runner.spawn(["A"])
    _ = try await runner.wine(["B"])
    let all = (1...5).flatMap { ["A-\($0)", "B-\($0)"] }
    #expect(await waitFor(5) {
        let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        return all.allSatisfy(text.contains)
    }, "\((try? String(contentsOf: log, encoding: .utf8)) ?? "")")
}
