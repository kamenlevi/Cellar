# Cellar M0 — Groundwork Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `cellar` command-line tool that installs a pinned Wine engine from Cellar's own GitHub release, creates a bottle, runs a Windows program in it, and imports Apple's D3DMetal from Kamen's own Game Porting Toolkit download.

**Architecture:** A Swift package with a library `CellarCore` holding all logic and a thin executable `cellar` built on swift-argument-parser. Engines are repackaged once by a shell script from Sikarugir's public engine and wrapper releases (minus D3DMetal), published as assets on `kamenlevi/Cellar` releases, and listed with SHA-256 in `engines.json`. All state lives under one root directory (`~/Library/Application Support/Cellar`, overridable with `CELLAR_HOME`) so tests and the acceptance run use a throwaway root.

**Tech Stack:** Swift 6.3 (SwiftPM, Swift Testing), swift-argument-parser 1.5.x, Foundation `Process`/`URLSession`/CryptoKit, `/usr/bin/tar`, `hdiutil`, `otool`, `gh` (packaging only).

**Spec:** `docs/superpowers/specs/2026-10-17-cellar-design.md` (milestone M0, sections 5, 6, 8)

## Global Constraints

- Machine: Apple Silicon M5 Pro, macOS 26.5. The Wine engine is x86_64 and runs under Rosetta 2.
- **Pinned engine:** Sikarugir `WS12WineSikarugir10.0_6.tar.xz` (Engines release `v1.0`) and runtime libraries from `Template-1.0.11.tar.xz` (Wrapper release `v1.0`). Cellar engine id: `sikarugir-10.0_6-c1`.
- **Engine source:** the app downloads engines only from `https://github.com/kamenlevi/Cellar/releases/…`, never from Sikarugir, Gcenx or any other host.
- **D3DMetal:** never redistributed. The packaged engine must not contain `renderer/d3dmetal` or `apple_gptk`. Cellar imports D3DMetal only from Kamen's own Game Porting Toolkit download (https://developer.apple.com/games/game-porting-toolkit/).
- **Credentials:** none, anywhere. Cellar never asks for, stores or types an Apple ID or Steam login.
- **Tests and automated runs are invisible and silent.** They never open a window, take focus or play sound on Kamen's Mac.
  - Headless Wine runs set `WINEDLLOVERRIDES` to include `winemac.drv=d` (null display driver) and `winecoreaudio.drv=d`.
  - Anything visible (the notepad check) is run by Kamen himself.
- **Small tests only.** Unit tests run in seconds with no network.
  - Integration tests that download the engine (a few hundred MB) or start Wine run only when `CELLAR_INTEGRATION=1` is set.
  - They use a temporary `CELLAR_HOME`.
- **Nothing is permanently deleted.** Removing a bottle or engine moves it to the Trash (`FileManager.trashItem`).
- **Stay inside Cellar's own Wine.** Cellar never touches Wine processes or prefixes outside its root: Sikarugir's Animal Well wrapper, Heroic and native Mac Steam keep working.
- **Outward-facing steps need Kamen's explicit yes at execution time:** creating the public GitHub repo and uploading release assets.

## Review Focus

1. **Paths with spaces and non-ASCII.** Bottle names like `Outer Wilds` and executables under folders like `Animal Well.app` must work end to end (tests in Tasks 5 and 6).
2. **Interrupted or corrupt download.** A bad SHA-256, a cut-off download or a full disk leaves no half-installed engine, and the next `cellar engine install` starts clean (Task 3).
3. **Rosetta missing.** `cellar doctor` says so with the exact fix (`softwareupdate --install-rosetta --agree-to-license`), and `cellar run` / `bottle create` refuse before starting Wine (Task 7).
4. **Stale wineserver.** `cellar bottle kill <name>` stops only that bottle's wineserver (scoped by `WINEPREFIX`) and never Sikarugir's or anyone else's (Task 6).
5. **Unsafe bottle names.** Names with `/`, `..`, a leading `.`, empty names or names over 64 characters are rejected before anything touches disk (Task 5).

---

## File Structure

```
Package.swift
Sources/CellarCore/
  CellarPaths.swift        root dir layout, CELLAR_HOME override
  EngineManifest.swift     engines.json model + bundled default manifest
  EngineStore.swift        download, verify, extract, install, list, remove
  WineEnvironment.swift    env vars for a (engine, bottle, mode) triple
  WineRunner.swift         run wine/wineserver via Process, log to file
  Bottle.swift             BottleName validation, bottle.json, create/list/remove/kill
  D3DMetalStore.swift      import from .dmg or folder, status
  Doctor.swift             system checks with fix instructions
  Resources/engines.json
  Resources/cellar-defaults.reg
Sources/cellar/
  Cellar.swift             ArgumentParser root + subcommands
Tests/CellarCoreTests/
  CellarPathsTests.swift  EngineManifestTests.swift  EngineStoreTests.swift
  WineEnvironmentTests.swift  BottleTests.swift  D3DMetalStoreTests.swift
  DoctorTests.swift  IntegrationTests.swift
  Fixtures/FakeEngine.swift   builds a tiny fake engine tarball at test time
scripts/
  package-engine.sh        Sikarugir engine + template → cellar engine tarball
  m0-acceptance.sh         the M0 "done when" run, in a throwaway CELLAR_HOME
README.md  LICENSE (MIT for Cellar's own code)  .gitignore
```

On-disk layout under the root (`CellarPaths`):

```
<root>/engines/<engine-id>/            ENGINE.json, wine/{bin,lib,share}, Frameworks/, renderer/{dxvk,d9vk,dxmt}
<root>/bottles/<name>/                 bottle.json, prefix/ (WINEPREFIX)
<root>/renderers/d3dmetal/<version>/   external/, wine/, IMPORT.json
<root>/downloads/                      partial downloads (*.part)
~/Library/Logs/Cellar/<bottle>.log     (under <root>/logs/ when CELLAR_HOME is set)
```

---

### Task 1: Package skeleton and paths

**Files:**
- Create: `Package.swift`, `Sources/CellarCore/CellarPaths.swift`, `Sources/cellar/Cellar.swift`, `Tests/CellarCoreTests/CellarPathsTests.swift`, `.gitignore` (`.build/`, `.superpowers/`, `*.part`), `LICENSE` (MIT, Kamen Levi), `README.md` (one paragraph + "M0: command line only")

**Interfaces:**
- Produces:
  - `struct CellarPaths { init(environment: [String:String] = ProcessInfo.processInfo.environment, home: URL = FileManager.default.homeDirectoryForCurrentUser) }`
  - Properties: `root, engines, bottles, d3dmetal, downloads, logs: URL`
  - Methods: `func engine(_ id: String) -> URL`, `func bottle(_ name: String) -> URL`
  - `cellar --version` prints `cellar 0.0.1 (M0)`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func defaultRootIsApplicationSupport() {
    let p = CellarPaths(environment: [:], home: URL(filePath: "/Users/k"))
    #expect(p.root.path == "/Users/k/Library/Application Support/Cellar")
    #expect(p.logs.path == "/Users/k/Library/Logs/Cellar")
    #expect(p.bottle("Outer Wilds").path == "/Users/k/Library/Application Support/Cellar/bottles/Outer Wilds")
}
@Test func cellarHomeOverridesEverything() {
    let p = CellarPaths(environment: ["CELLAR_HOME": "/tmp/ch"], home: URL(filePath: "/Users/k"))
    #expect(p.root.path == "/tmp/ch")
    #expect(p.logs.path == "/tmp/ch/logs")
    #expect(p.engine("sikarugir-10.0_6-c1").path == "/tmp/ch/engines/sikarugir-10.0_6-c1")
}
```

- [ ] **Step 2: Run `swift test --filter CellarPathsTests`.** Expected: FAIL (CellarPaths not defined).
- [ ] **Step 3: Implement.** `Package.swift`: platforms `.macOS(.v26)`, products `cellar` (executable) and `CellarCore` (library, with `resources: [.process("Resources")]`), dependency `swift-argument-parser` from `1.5.0`. Implement `CellarPaths` and a root `Cellar: AsyncParsableCommand` with `version: "cellar 0.0.1 (M0)"`.
- [ ] **Step 4: Run `swift test --filter CellarPathsTests && swift run cellar --version`.** Expected: PASS; prints `cellar 0.0.1 (M0)`.
- [ ] **Step 5: Commit.** `git commit -m "Cellar package skeleton and on-disk layout"`

---

### Task 2: Package and mirror the engine

This task produces the one engine Cellar uses. It runs on Kamen's Mac, once.

**Files:**
- Create: `scripts/package-engine.sh`, `Sources/CellarCore/Resources/engines.json`, `Sources/CellarCore/EngineManifest.swift`, `Tests/CellarCoreTests/EngineManifestTests.swift`, `docs/engines.md` (where each piece came from, licences, how to rebuild)

**Interfaces:**
- Produces:
  - `struct EngineManifest: Codable { var engines: [EngineEntry]; static func bundled() throws -> EngineManifest; var defaultEngine: EngineEntry }`
  - `struct EngineEntry: Codable, Equatable { id: String; wineVersion: String; url: URL; sha256: String; size: Int64; isDefault: Bool }`
  - The release asset `cellar-engine-sikarugir-10.0_6-c1.tar.xz`, extracting to a single top-level folder `sikarugir-10.0_6-c1/`. That folder holds:
    - `ENGINE.json`: `{"id","wineVersion","sources":{"engine":"WS12WineSikarugir10.0_6.tar.xz","template":"Template-1.0.11.tar.xz"},"builtAt"}`
    - `wine/`, `Frameworks/`, `renderer/`

- [ ] **Step 1: Write `scripts/package-engine.sh <workdir>`.** Steps, in this order:
  - Download both Sikarugir assets with `gh release download v1.0 -R Sikarugir-App/Engines -p WS12WineSikarugir10.0_6.tar.xz` and `gh release download v1.0 -R Sikarugir-App/Wrapper -p Template-1.0.11.tar.xz`.
  - Extract both into separate empty directories inside `<workdir>`.
  - Take `wine/` from the engine.
  - From the template take `Contents/Frameworks/*` except `renderer/` and `SikarugirSdk.framework`, plus `Contents/Frameworks/renderer/{dxvk,d9vk,dxmt}`.
  - Fail if any path containing `d3dmetal` or `apple_gptk` ends up in the output.
  - Write `ENGINE.json`, tar with `tar -cJf`, and print the SHA-256 (`shasum -a 256`) and size.
  - Add a `--check <folder>` mode. For every Mach-O under `wine/` it runs `otool -L` and fails on any `@rpath/` dependency that isn't present in `Frameworks/`.
- [ ] **Step 2: Run `scripts/package-engine.sh "$TMPDIR/cellar-pkg"` then `scripts/package-engine.sh --check "$TMPDIR/cellar-pkg/out/sikarugir-10.0_6-c1"`.** Expected: a tarball of a few hundred MB (the two Sikarugir sources are 166 MB and 116 MB compressed); `--check` prints `all dependencies resolve`; `grep -ri d3dmetal` over the output folder prints nothing.
- [ ] **Step 3: Stop and ask Kamen.** Ask for his explicit yes to:
  - create the public repo `kamenlevi/Cellar` and push `main`;
  - create release `engine-sikarugir-10.0_6-c1`;
  - upload the tarball to it.

  Then do exactly that with `gh repo create kamenlevi/Cellar --public --source . --push`, `gh release create engine-sikarugir-10.0_6-c1 <tarball> --notes-file docs/engines.md`.
- [ ] **Step 4: Write the failing tests**

```swift
@Test func bundledManifestPinsTheOneEngine() throws {
    let m = try EngineManifest.bundled()
    #expect(m.defaultEngine.id == "sikarugir-10.0_6-c1")
    #expect(m.defaultEngine.url.host() == "github.com")
    #expect(m.defaultEngine.url.path().hasPrefix("/kamenlevi/Cellar/releases/download/"))
    #expect(m.defaultEngine.sha256.count == 64)
    #expect(m.engines.filter(\.isDefault).count == 1)
}
```

- [ ] **Step 5: Run `swift test --filter EngineManifestTests`.** Expected: FAIL.
- [ ] **Step 6: Implement `EngineManifest` and fill `engines.json`.** Use the real release URL, SHA-256 and size from Steps 2–3.
- [ ] **Step 7: Run `swift test --filter EngineManifestTests`.** Expected: PASS.
- [ ] **Step 8: Commit.** `git commit -m "Package the pinned engine from Sikarugir parts, without D3DMetal, and pin it"`

---

### Task 3: Install engines safely

**Files:**
- Create: `Sources/CellarCore/EngineStore.swift`, `Tests/CellarCoreTests/EngineStoreTests.swift`, `Tests/CellarCoreTests/Fixtures/FakeEngine.swift`
- Modify: `Sources/cellar/Cellar.swift` (add `engine install [id]`, `engine list`, `engine remove <id>`)

**Interfaces:**
- Consumes: `CellarPaths`, `EngineEntry`
- Produces:
  - `struct InstalledEngine { id: String; root: URL; wineBinary: URL; wineserverBinary: URL; frameworks: URL }`
  - `final class EngineStore { init(paths: CellarPaths, session: URLSession = .shared) }`
  - `func install(_ entry: EngineEntry, progress: (Int64, Int64) -> Void = { _,_ in }) async throws -> InstalledEngine`
  - `func installed() throws -> [InstalledEngine]`, `func installedEngine(id: String) throws -> InstalledEngine?`, `func remove(id: String) throws`
  - `enum EngineError: Error, Equatable { case checksumMismatch(expected: String, actual: String), badLayout(String), notInstalled(String) }`
  - Fixture: `FakeEngine.makeTarball(id: String, in dir: URL) throws -> (url: URL, sha256: String, size: Int64)`. It builds a tar.xz holding `<id>/ENGINE.json`, `<id>/wine/bin/wine` and `<id>/wine/bin/wineserver` (shell stubs, mode 0755) and `<id>/Frameworks/`.

- [ ] **Step 1: Write the failing tests** (all against a temp `CELLAR_HOME` and `file://` fixture URLs)

```swift
@Test func installsAndListsEngine() async throws { /* install fake; installed().map(\.id) == [id]; wineBinary exists & executable */ }
@Test func checksumMismatchInstallsNothing() async throws {
    /* entry with sha256 = String(repeating: "0", count: 64)
       await #expect(throws: EngineError.checksumMismatch(...)) — compare case only
       installed().isEmpty; downloads/ has no *.part; engines/ has no temp dirs */
}
@Test func truncatedDownloadInstallsNothing() async throws { /* fixture file cut to half size, real sha → checksumMismatch, nothing left behind */ }
@Test func missingWineBinaryIsBadLayout() async throws { /* tarball without wine/bin/wine → .badLayout, nothing installed */ }
@Test func reinstallOverExistingIsNoOp() async throws { /* second install of same id returns same InstalledEngine without re-downloading (fixture file deleted before 2nd call) */ }
@Test func removeMovesToTrash() async throws { /* remove(id) → engine dir gone from engines/, installed().isEmpty */ }
```

- [ ] **Step 2: Run `swift test --filter EngineStoreTests`.** Expected: FAIL.
- [ ] **Step 3: Implement `EngineStore`.**
  - Download to `downloads/<id>.part` with `URLSession.download`.
  - Verify SHA-256 with CryptoKit, streaming in 1 MB chunks.
  - Extract with `/usr/bin/tar -xJf` into `engines/.staging-<uuid>/`.
  - Check that `wine/bin/wine` and `wine/bin/wineserver` exist and are executable.
  - Install with `FileManager.moveItem` to `engines/<id>`.
  - On any error, remove `.part` and staging. These are Cellar's own temporary files, so plain removal is fine; only installed engines and bottles go to the Trash.
  - `remove` uses `trashItem`.
- [ ] **Step 4: Run `swift test --filter EngineStoreTests`.** Expected: PASS (6 tests).
- [ ] **Step 5: Commit.** `git commit -m "Install engines atomically with checksum verification"`

---

### Task 4: Wine environment and runner

**Files:**
- Create: `Sources/CellarCore/WineEnvironment.swift`, `Sources/CellarCore/WineRunner.swift`, `Tests/CellarCoreTests/WineEnvironmentTests.swift`

**Interfaces:**
- Consumes: `InstalledEngine`, `CellarPaths`
- Produces:
  - `enum WineMode { case headless, interactive }`
  - `struct WineEnvironment { static func make(engine: InstalledEngine, prefix: URL, mode: WineMode, base: [String:String] = ProcessInfo.processInfo.environment) -> [String:String] }`
  - `struct WineResult { exitCode: Int32; output: String }`. `output` is the captured stdout+stderr, kept to the last 64 KB.
  - `struct WineRunner { init(engine: InstalledEngine, prefix: URL, mode: WineMode, logFile: URL) }`
  - `func wine(_ args: [String], cwd: URL? = nil) async throws -> WineResult`
  - `func wineserver(_ args: [String]) async throws -> WineResult`
  - Every run appends a header line, `=== <ISO date> wine <args>`, and the full output to `logFile`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func headlessEnvironment() {
    let env = WineEnvironment.make(engine: fakeEngine, prefix: URL(filePath: "/tmp/b/prefix"), mode: .headless, base: ["HOME": "/Users/k", "PATH": "/usr/bin"])
    #expect(env["WINEPREFIX"] == "/tmp/b/prefix")
    #expect(env["DYLD_FALLBACK_LIBRARY_PATH"]!.hasPrefix(fakeEngine.frameworks.path))
    #expect(env["WINEDLLOVERRIDES"]!.contains("winemac.drv=d"))
    #expect(env["WINEDLLOVERRIDES"]!.contains("winecoreaudio.drv=d"))
    #expect(env["WINEDLLOVERRIDES"]!.contains("mscoree,mshtml="))
    #expect(env["WINEDEBUG"] == "-all")
    #expect(env["PATH"]!.hasPrefix(fakeEngine.wineBinary.deletingLastPathComponent().path))
}
@Test func interactiveKeepsDisplayAndAudio() {
    let env = WineEnvironment.make(engine: fakeEngine, prefix: URL(filePath: "/tmp/p"), mode: .interactive, base: [:])
    #expect(!(env["WINEDLLOVERRIDES"] ?? "").contains("winemac.drv=d"))
    #expect(!(env["WINEDLLOVERRIDES"] ?? "").contains("winecoreaudio.drv=d"))
}
@Test func runnerLogsAndReturnsExitCode() async throws {
    /* fake engine whose wine stub is: #!/bin/sh\necho "args:$@"; echo "pfx:$WINEPREFIX"; exit 3
       run wine(["cmd","/c","echo hi"]) → exitCode 3, output contains "args:cmd /c echo hi" and the prefix path;
       log file contains "=== " header and same output */
}
@Test func argumentsWithSpacesArePassedIntact() async throws {
    /* stub prints each arg on its own line; wine(["C:\\Program Files\\Animal Well\\Animal Well.exe"]) → that exact line */
}
```

- [ ] **Step 2: Run `swift test --filter WineEnvironmentTests`.** Expected: FAIL.
- [ ] **Step 3: Implement.**
  - `mscoree,mshtml=` stops the Mono and Gecko install prompts during `wineboot`.
  - `DYLD_FALLBACK_LIBRARY_PATH` = `<engine>/Frameworks:/usr/lib`. This is the lesson from spec section 8.
  - The runner uses `Process` with `executableURL` = the stub/binary directly. Never go through a shell, so spaces survive.
- [ ] **Step 4: Run `swift test --filter WineEnvironmentTests`.** Expected: PASS (4 tests).
- [ ] **Step 5: Commit.** `git commit -m "Wine environment (headless by default) and a logging runner"`

---

### Task 5: Bottles

**Files:**
- Create: `Sources/CellarCore/Bottle.swift`, `Sources/CellarCore/Resources/cellar-defaults.reg`, `Tests/CellarCoreTests/BottleTests.swift`
- Modify: `Sources/cellar/Cellar.swift` (add `bottle create <name> [--engine id]`, `bottle list`, `bottle remove <name>`)

**Interfaces:**
- Consumes: `CellarPaths`, `EngineStore`, `WineRunner`, `WineEnvironment`
- Produces:
  - `struct BottleName { init(_ raw: String) throws(BottleError); let value: String }`
  - `struct BottleInfo: Codable { name: String; engineId: String; created: Date; cellarVersion: String }`
  - `final class BottleStore { init(paths: CellarPaths, engines: EngineStore) }`
  - `func create(_ name: BottleName, engineId: String?) async throws -> BottleInfo`. With `nil` it uses the manifest default, installing it if missing.
  - `func list() throws -> [BottleInfo]`, `func remove(_ name: BottleName) throws`
  - `func runner(for name: BottleName, mode: WineMode) throws -> WineRunner`
  - `enum BottleError: Error, Equatable { case invalidName(String), exists(String), notFound(String) }`
- `cellar-defaults.reg` (exact content):

```
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Wine\Mac Driver]
"RetinaMode"="y"
```

- [ ] **Step 1: Write the failing tests**

```swift
@Test(arguments: ["Outer Wilds", "Chants of Sennaar", "Rain_World-2", "Łódź"])
func validNames(_ s: String) throws { #expect(try BottleName(s).value == s) }
@Test(arguments: ["", "a/b", "..", ".hidden", "../x", String(repeating: "x", count: 65), "a\u{0}b"])
func invalidNames(_ s: String) { #expect(throws: BottleError.self) { try BottleName(s) } }
@Test func createWritesInfoAndRunsWinebootThenDefaults() async throws {
    /* fake engine whose wine stub appends "$@" to a calls file and creates $WINEPREFIX/user.reg;
       create("Outer Wilds") → bottle.json decodes with engineId == fake id;
       calls file lines == ["wineboot --init", "regedit /S <path ending cellar-defaults.reg>"];
       last wineserver call is "-w" */
}
@Test func createTwiceThrowsExists() async throws { /* second create → .exists("Outer Wilds") */ }
@Test func removeMovesToTrashAndListForgetsIt() async throws { }
```

- [ ] **Step 2: Run `swift test --filter BottleTests`.** Expected: FAIL.
- [ ] **Step 3: Implement.**
  - Create `bottles/<name>/prefix`.
  - Run, all headless: `wine wineboot --init`, then `wine regedit /S <copied cellar-defaults.reg>`, then `wineserver -w`.
  - Write `bottle.json` last. A bottle without `bottle.json` is ignored by `list()` and cleaned up by the next `create` of the same name.
- [ ] **Step 4: Run `swift test --filter BottleTests`.** Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "Bottles: safe names, wineboot, Retina on by default"`

---

### Task 6: Run programs and recover stuck bottles

**Files:**
- Modify: `Sources/CellarCore/Bottle.swift`, `Sources/cellar/Cellar.swift` (add `run <bottle> <program> [args…] [--headless]`, `bottle kill <name>`)
- Test: `Tests/CellarCoreTests/BottleTests.swift`

**Interfaces:**
- Consumes: Task 5's `BottleStore`
- Produces:
  - `func run(_ name: BottleName, program: String, arguments: [String], mode: WineMode) async throws -> WineResult` on `BottleStore`. `program` is either a macOS path (absolute or relative to the cwd) or a Windows path (`C:\…`). Cellar passes macOS paths through unchanged and sets the working directory to the program's folder.
  - `func kill(_ name: BottleName) async throws`. It runs `wineserver -k` with this bottle's `WINEPREFIX`, then `wineserver -w`.
  - `cellar run` defaults to `.interactive`. `--headless` is for scripts and tests.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func runMacPathSetsWorkingDirectory() async throws {
    /* stub prints "cwd:$(pwd)"; program "/tmp/x/Animal Well.app/Contents/game.exe" (created) → output contains "cwd:/tmp/x/Animal Well.app/Contents" */
}
@Test func runWindowsPathPassesThrough() async throws { /* program #"C:\windows\system32\cmd.exe"# → stub receives it unchanged as first arg */ }
@Test func runUnknownBottleThrowsNotFound() async throws { }
@Test func killIsScopedToThisBottle() async throws {
    /* wineserver stub records "$WINEPREFIX $@"; kill("A") → records exactly ["<A prefix> -k", "<A prefix> -w"], nothing for bottle B */
}
```

- [ ] **Step 2: Run `swift test --filter BottleTests`.** Expected: the 4 new tests FAIL.
- [ ] **Step 3: Implement `run` and `kill`.**
- [ ] **Step 4: Run `swift test`.** Expected: all PASS.
- [ ] **Step 5: Commit.** `git commit -m "Run Windows programs in a bottle; kill only that bottle's wineserver"`

---

### Task 7: D3DMetal import and `cellar doctor`

**Files:**
- Create: `Sources/CellarCore/D3DMetalStore.swift`, `Sources/CellarCore/Doctor.swift`, `Tests/CellarCoreTests/D3DMetalStoreTests.swift`, `Tests/CellarCoreTests/DoctorTests.swift`
- Modify: `Sources/cellar/Cellar.swift` (add `d3dmetal import <dmg-or-folder>`, `d3dmetal status`, `doctor`). `bottle create` and `run` call `Doctor.requireRosetta()` first.

**Interfaces:**
- Produces:
  - `struct D3DMetalImport: Codable { version: String; importedAt: Date; source: String }`
  - `final class D3DMetalStore { init(paths: CellarPaths) }`
  - `func importFrom(_ url: URL) async throws -> D3DMetalImport`, `func current() throws -> D3DMetalImport?`
  - `enum D3DMetalError: Error, Equatable { case notFound(String) }`
  - `struct Check { let name: String; let ok: Bool; let fix: String? }`
  - `struct Doctor { init(paths: CellarPaths, rosettaProbe: () -> Bool = Doctor.systemRosettaProbe) }`
  - `func run() throws -> [Check]`, `func requireRosetta() throws`
  - `static func systemRosettaProbe() -> Bool` runs `/usr/bin/arch -x86_64 /usr/bin/true` and returns exit 0.
- What a valid D3DMetal source is: the directory the Game Porting Toolkit evaluation environment calls `redist/lib`. It contains `external/D3DMetal.framework`, `external/libd3dshared.dylib` and `wine/x86_64-windows/d3d12.dll`.
  - If given a `.dmg`, Cellar mounts it with `hdiutil attach -readonly -nobrowse -mountpoint <tmp>`.
  - It then searches mounted volumes (including any nested evaluation-environment `.dmg`, mounted the same way) for that directory, to depth 6.
  - It detaches everything it attached, including on error.
  - Version comes from `D3DMetal.framework/Resources/Info.plist` `CFBundleShortVersionString`.
  - It copies `external/` and `wine/` into `renderers/d3dmetal/<version>/`.
- Doctor checks, in this order, with these exact fix texts:
  - `Rosetta 2`. Fix: `Run: softwareupdate --install-rosetta --agree-to-license`
  - `Engine`. Fix: `Run: cellar engine install`
  - `D3DMetal`. Fix: `Sign in at https://developer.apple.com/games/game-porting-toolkit/ (free Apple account), download the Game Porting Toolkit .dmg, then run: cellar d3dmetal import ~/Downloads/<file>.dmg`. This one is marked optional in M0, so `doctor` exits 0 when it is the only failure.
  - `Free disk space ≥ 5 GB`. Fix: `Free up space on the startup disk`

- [ ] **Step 1: Write the failing tests**

```swift
@Test func importsFromFolderLayout() async throws {
    /* build temp tree a/b/redist/lib/{external/D3DMetal.framework/Resources/Info.plist (CFBundleShortVersionString 3.0), external/libd3dshared.dylib, wine/x86_64-windows/d3d12.dll};
       importFrom(a) → version "3.0"; renderers/d3dmetal/3.0/wine/x86_64-windows/d3d12.dll exists; current()?.version == "3.0" */
}
@Test func folderWithoutD3DMetalThrowsNotFound() async throws { }
@Test func doctorReportsMissingRosettaWithFix() throws {
    let checks = try Doctor(paths: tmpPaths, rosettaProbe: { false }).run()
    #expect(checks.first?.name == "Rosetta 2"); #expect(checks.first?.ok == false)
    #expect(checks.first?.fix == "Run: softwareupdate --install-rosetta --agree-to-license")
}
@Test func requireRosettaThrowsWhenMissing() { #expect(throws: (any Error).self) { try Doctor(paths: tmpPaths, rosettaProbe: { false }).requireRosetta() } }
@Test func d3dmetalMissingGivesAppleInstructions() throws { /* fix contains "developer.apple.com/games/game-porting-toolkit" and "cellar d3dmetal import" */ }
```

- [ ] **Step 2: Run `swift test --filter "D3DMetalStoreTests|DoctorTests"`.** Expected: FAIL.
- [ ] **Step 3: Implement both.** The `.dmg` path is exercised by Kamen in Task 8, not by unit tests.
- [ ] **Step 4: Run `swift test`.** Expected: all PASS.
- [ ] **Step 5: Commit.** `git commit -m "Import D3DMetal from Kamen's own GPTk download; cellar doctor"`

---

### Task 8: M0 acceptance

**Files:**
- Create: `Tests/CellarCoreTests/IntegrationTests.swift`, `scripts/m0-acceptance.sh`
- Modify: `README.md` (usage: doctor, engine install, bottle create, run, kill, d3dmetal import)

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Write integration tests.** These are gated with `.enabled(if: ProcessInfo.processInfo.environment["CELLAR_INTEGRATION"] == "1")`, use a temp `CELLAR_HOME` and run fully headless.

```swift
@Test func realEngineInstallsFromGitHubAndRunsCmd() async throws {
    /* EngineStore.install(EngineManifest.bundled().defaultEngine) from the real release URL;
       BottleStore.create("Cellar Test"); run(program: "cmd", arguments: ["/c","echo","cellar-ok"], mode: .headless)
       → exitCode == 0, output contains "cellar-ok";
       prefix/user.reg contains "\"RetinaMode\"=\"y\"";
       kill("Cellar Test") returns; then BottleStore.remove */
}
```

- [ ] **Step 2: Run `CELLAR_INTEGRATION=1 swift test --filter IntegrationTests`.** Expected: PASS. It takes a few minutes because of the engine download. No window and no sound appear. Check `lsappinfo list | grep -c '"wine"'` afterwards: it shows no new Foreground Wine apps.
- [ ] **Step 3: Write `scripts/m0-acceptance.sh`.** In order, it:
  - builds release (`swift build -c release`);
  - sets `CELLAR_HOME=$(mktemp -d)` to simulate a fresh user;
  - runs `cellar doctor`, `cellar engine install`, `cellar bottle create "M0 Check"` and `cellar run --headless "M0 Check" cmd /c echo cellar-ok`;
  - asserts `cellar-ok` is in the output;
  - prints `M0 acceptance: PASS` and the temp root path, leaving it in place for Kamen to look at.

  It must not read anything from `~/Applications/Sikarugir`, Heroic's folders or `/opt/homebrew`. Enforce that with `env -i HOME=$HOME PATH=/usr/bin:/bin:/usr/sbin:/sbin`.
- [ ] **Step 4: Run `scripts/m0-acceptance.sh`.** Expected: ends with `M0 acceptance: PASS`.
- [ ] **Step 5: Hand Kamen two manual checks.**
  - Check 1: `cellar run "M0 Check" notepad`. A Windows Notepad window appears at the right Retina size. He closes it.
  - Check 2: after downloading the Game Porting Toolkit `.dmg` from Apple himself, `cellar d3dmetal import ~/Downloads/<file>.dmg`, then `cellar d3dmetal status`. It shows the version.
  - Record his results in `docs/m0-signoff.md`.
- [ ] **Step 6: Commit and push.** `git commit -m "M0 acceptance: fresh-root install, bottle and run"`. Push to `main` only if the repo from Task 2 exists and Kamen has said yes to pushing.
