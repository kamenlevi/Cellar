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

/// With Retina mode on, Windows must also be told the screen is 200% (192 DPI), as Windows itself
/// would be on a Retina-class display; at the default 96 DPI every menu and font draws at half size.
@Test func defaultsSetWindowsTo200PercentScaling() throws {
    let url = try #require(BottleStore.defaultsRegistryFile)
    let text = try String(contentsOf: url, encoding: .utf8)
    let sections = text.components(separatedBy: "\n[").map { "[" + $0 }
    for key in [#"[HKEY_CURRENT_USER\Control Panel\Desktop]"#,
                #"[HKEY_LOCAL_MACHINE\System\CurrentControlSet\Hardware Profiles\Current\Software\Fonts]"#] {
        let section = try #require(sections.first { $0.hasPrefix(key) }, "\(key) missing")
        #expect(section.contains(#""LogPixels"=dword:000000c0"#), "\(key) has no 192 DPI")
    }
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

// MARK: - Engine replacement

private func manifest(_ entries: [(id: String, replaces: [String])]) -> EngineManifest {
    EngineManifest(engines: entries.enumerated().map { i, e in
        EngineEntry(id: e.id, wineVersion: "10.0", url: URL(string: "https://github.com/kamenlevi/Cellar")!,
                    sha256: String(repeating: "0", count: 64), size: 1, isDefault: i == 0, replaces: e.replaces)
    })
}

@Test func aBottleOnAReplacedEngineMovesToItsReplacement() async throws {
    let rig = try Rig()
    let name = try BottleName("Steam")
    _ = try await rig.store.create(name, engineId: "fake")
    try FakeEngine.installed(id: "fake-c2", in: rig.tmp.paths.engines)
    #expect(try await rig.store.moveToNewerEngine(name, manifest: manifest([("fake-c2", ["fake"])])) == "fake-c2")
    #expect(try rig.store.info(name).engineId == "fake-c2")
}

@Test func aBottleOnACurrentEngineStays() async throws {
    let rig = try Rig()
    let name = try BottleName("Steam")
    _ = try await rig.store.create(name, engineId: "fake")
    #expect(try await rig.store.moveToNewerEngine(name, manifest: manifest([("other", ["older"]), ("fake", [])])) == nil)
    #expect(try rig.store.info(name).engineId == "fake")
}

// MARK: - M4: clones and engine choice

@Test func aCloneIsIndependentOfItsSource() async throws {
    let rig = try Rig()
    let steam = try BottleName("Steam"), copy = try BottleName("Steam-m4")
    _ = try await rig.store.create(steam, engineId: "fake")
    let file = "prefix/drive_c/users/kamen/save.dat"
    let original = rig.tmp.paths.bottle("Steam").appending(path: file)
    try FileManager.default.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("before".utf8).write(to: original)
    let info = try rig.store.clone(steam, to: copy)
    #expect(info.name == "Steam-m4")
    #expect(info.engineId == "fake")
    try Data("changed in the clone".utf8).write(to: rig.tmp.paths.bottle("Steam-m4").appending(path: file))
    #expect(try String(contentsOf: original, encoding: .utf8) == "before")
    #expect(try rig.store.info(steam).name == "Steam")
}

@Test func cloningOntoAnExistingBottleIsRefused() async throws {
    let rig = try Rig()
    _ = try await rig.store.create(try BottleName("Steam"), engineId: "fake")
    _ = try await rig.store.create(try BottleName("Steam-m4"), engineId: "fake")
    #expect(throws: BottleError.exists("Steam-m4")) { try rig.store.clone(try BottleName("Steam"), to: try BottleName("Steam-m4")) }
}

@Test func setEngineNeedsTheEngineInstalled() async throws {
    let rig = try Rig()
    let name = try BottleName("Steam-m4")
    _ = try await rig.store.create(name, engineId: "fake")
    #expect(throws: EngineError.notInstalled("missing")) { try rig.store.setEngine(name, to: "missing") }
    try FakeEngine.installed(id: "crossover-25.1.1-c1", in: rig.tmp.paths.engines)
    try rig.store.setEngine(name, to: "crossover-25.1.1-c1")
    #expect(try rig.store.info(name).engineId == "crossover-25.1.1-c1")
}

@Test func anEngineThatReplacesNothingMovesNoBottle() async throws {
    let rig = try Rig()
    let name = try BottleName("Steam")
    _ = try await rig.store.create(name, engineId: "fake")
    try FakeEngine.installed(id: "crossover-25.1.1-c1", in: rig.tmp.paths.engines)
    #expect(try await rig.store.moveToNewerEngine(name, manifest: manifest([("fake", []), ("crossover-25.1.1-c1", [])])) == nil)
    #expect(try rig.store.info(name).engineId == "fake")
}

@Test func cloningARunningBottleIsRefused() async throws {
    let rig = try Rig()
    let steam = try BottleName("Steam")
    _ = try await rig.store.create(steam, engineId: "fake")
    let servers = rig.tmp.url.appending(path: "wine-servers")
    let socketDir = BottleStore.wineServerFolder(for: rig.tmp.paths.bottle("Steam").appending(path: "prefix"), in: servers)
    try FileManager.default.createDirectory(at: socketDir, withIntermediateDirectories: true)
    try Data().write(to: socketDir.appending(path: "socket"))
    #expect(throws: BottleError.inUse("Steam")) { try rig.store.clone(steam, to: try BottleName("Steam-m4"), wineServers: servers) }
}

@Test func theWineServerFolderIsNamedAsWineNamesIt() throws {
    // Wine: /tmp/.wine-<uid>/server-<st_dev hex>-<st_ino hex>, for the prefix folder.
    let tmp = try TempRoot()
    let st = try FileManager.default.attributesOfItem(atPath: tmp.url.path)
    let dev = String((st[.systemNumber] as! NSNumber).uint64Value, radix: 16)
    let ino = String((st[.systemFileNumber] as! NSNumber).uint64Value, radix: 16)
    #expect(BottleStore.wineServerFolder(for: tmp.url, in: URL(filePath: "/tmp/.wine-501")).path == "/tmp/.wine-501/server-\(dev)-\(ino)")
}
