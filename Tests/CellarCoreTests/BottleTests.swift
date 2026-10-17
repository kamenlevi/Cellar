import Foundation
import Testing
@testable import CellarCore

/// A bottle store over a fake engine whose `wine` and `wineserver` record every call.
private struct Rig {
    let tmp: TempRoot
    let store: BottleStore
    let calls: URL
    let serverCalls: URL

    init(wine extra: String = "") throws {
        tmp = try TempRoot()
        calls = tmp.url.appending(path: "calls.txt")
        serverCalls = tmp.url.appending(path: "server-calls.txt")
        let wine = """
        #!/bin/sh
        printf "%s\n" "$*" >> '\(calls.path)'
        mkdir -p "$WINEPREFIX" && touch "$WINEPREFIX/user.reg"
        \(extra)
        """
        let wineserver = "#!/bin/sh\necho \"$WINEPREFIX $*\" >> '\(serverCalls.path)'\n"
        try FakeEngine.installed(id: "fake", in: tmp.paths.engines, wine: wine, wineserver: wineserver)
        store = BottleStore(paths: tmp.paths, engines: EngineStore(paths: tmp.paths, discard: TempRoot.discard),
                            discard: TempRoot.discard)
    }

    func lines(_ url: URL) -> [String] {
        ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }
}

// MARK: - Task 5

@Test(arguments: ["Outer Wilds", "Chants of Sennaar", "Rain_World-2", "Łódź"])
func validNames(_ s: String) throws { #expect(try BottleName(s).value == s) }

@Test(arguments: ["", "a/b", "..", ".hidden", "../x", String(repeating: "x", count: 65), "a\u{0}b", "a:b"])
func invalidNames(_ s: String) { #expect(throws: BottleError.self) { try BottleName(s) } }

@Test func createWritesInfoAndRunsWinebootThenDefaults() async throws {
    let rig = try Rig()
    let info = try await rig.store.create(BottleName("Outer Wilds"), engineId: "fake")
    #expect(info.engineId == "fake")
    let saved = try JSONDecoder.cellar.decode(BottleInfo.self, from: Data(contentsOf:
        rig.tmp.paths.bottle("Outer Wilds").appending(path: "bottle.json")))
    #expect(saved.name == "Outer Wilds")
    let calls = rig.lines(rig.calls)
    #expect(calls.count == 2)
    #expect(calls.first == "wineboot --init")
    #expect(calls.last?.hasPrefix("regedit /S ") == true)
    #expect(calls.last?.hasSuffix("cellar-defaults.reg") == true)
    #expect(rig.lines(rig.serverCalls).last?.hasSuffix(" -w") == true)
    #expect(try rig.store.list().map(\.name) == ["Outer Wilds"])
}

@Test func defaultsTurnRetinaModeOn() throws {
    let url = try #require(BottleStore.defaultsRegistryFile)
    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(text.contains(#"[HKEY_CURRENT_USER\Software\Wine\Mac Driver]"#))
    #expect(text.contains(#""RetinaMode"="y""#))
}

@Test func createTwiceThrowsExists() async throws {
    let rig = try Rig()
    _ = try await rig.store.create(BottleName("Outer Wilds"), engineId: "fake")
    await #expect(throws: BottleError.exists("Outer Wilds")) {
        try await rig.store.create(BottleName("Outer Wilds"), engineId: "fake")
    }
}

@Test func halfMadeBottleIsIgnoredAndReplaced() async throws {
    let rig = try Rig()
    try FileManager.default.createDirectory(at: rig.tmp.paths.bottle("Journey").appending(path: "prefix"),
                                            withIntermediateDirectories: true)
    #expect(try rig.store.list().isEmpty)
    _ = try await rig.store.create(BottleName("Journey"), engineId: "fake")
    #expect(try rig.store.list().map(\.name) == ["Journey"])
}

@Test func removeForgetsBottle() async throws {
    let rig = try Rig()
    _ = try await rig.store.create(BottleName("Outer Wilds"), engineId: "fake")
    try rig.store.remove(BottleName("Outer Wilds"))
    #expect(try rig.store.list().isEmpty)
    #expect(throws: BottleError.notFound("Outer Wilds")) { try rig.store.remove(BottleName("Outer Wilds")) }
}

// MARK: - Task 6

@Test func runMacPathSetsWorkingDirectory() async throws {
    let rig = try Rig(wine: "echo \"cwd:$(pwd)\"")
    _ = try await rig.store.create(BottleName("Animal Well"), engineId: "fake")
    let folder = rig.tmp.url.appending(path: "x/Animal Well.app/Contents")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let exe = folder.appending(path: "game.exe")
    try Data().write(to: exe)
    let result = try await rig.store.run(BottleName("Animal Well"), program: exe.path, arguments: [], mode: .headless)
    // The temp folder lives under /var, which the child sees as /private/var.
    let cwd = result.output.split(separator: "\n").first { $0.hasPrefix("cwd:") }.map { String($0.dropFirst(4)) }
    #expect(cwd.map { URL(filePath: $0).standardizedFileURL.path.hasSuffix(folder.path) || $0.hasSuffix(folder.path) } == true,
            "\(result.output)")
    #expect(rig.lines(rig.calls).last == exe.path)
}

@Test func runWindowsPathPassesThrough() async throws {
    let rig = try Rig()
    _ = try await rig.store.create(BottleName("Journey"), engineId: "fake")
    let exe = #"C:\windows\system32\cmd.exe"#
    _ = try await rig.store.run(BottleName("Journey"), program: exe, arguments: ["/c", "echo", "hi"], mode: .headless)
    #expect(rig.lines(rig.calls).last == "\(exe) /c echo hi")
}

@Test func runUnknownBottleThrowsNotFound() async throws {
    let rig = try Rig()
    await #expect(throws: BottleError.notFound("Nope")) {
        try await rig.store.run(BottleName("Nope"), program: "cmd", arguments: [], mode: .headless)
    }
}

@Test func killIsScopedToThisBottle() async throws {
    let rig = try Rig()
    _ = try await rig.store.create(BottleName("A"), engineId: "fake")
    _ = try await rig.store.create(BottleName("B"), engineId: "fake")
    try FileManager.default.removeItem(at: rig.serverCalls)
    try await rig.store.kill(BottleName("A"))
    let prefixA = rig.tmp.paths.bottle("A").appending(path: "prefix").path
    #expect(rig.lines(rig.serverCalls) == ["\(prefixA) -k", "\(prefixA) -w"])
}
