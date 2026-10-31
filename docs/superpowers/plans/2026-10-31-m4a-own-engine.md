# M4 phase A: Cellar's own engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Steam bottle runs on a Wine engine Cellar builds from CodeWeavers' public CrossOver source, matching engine c2 on every game, with nothing worse.

**Architecture:**
- A build script compiles CrossOver 25.1.1's Wine on a GitHub Actions Intel macOS runner and applies Cellar's patches. It then lays the result out exactly like today's engine (`wine/`, `Frameworks/`, `renderer/`, `ENGINE.json`), using the same runtime libraries from Sikarugir's wrapper template.
- Cellar gains two things: running its Steam on another bottle, and an APFS clone of a bottle. Together they let both engines be compared on the same games, and the real bottle switches only after Kamen signs off.
- A comparison in CellarCore turns the reports of muted `cellar check` runs into a pass/fail per game.

**Tech Stack:** Swift 6 / swift-testing (CellarCore, `cellar`). Bash build scripts. GitHub Actions (`macos-15-intel`). Wine/CrossOver C and Objective-C sources. Homebrew build tools on the runner only.

**Spec:** `docs/superpowers/specs/2026-10-31-m4-own-engine-native-fullscreen-design.md`, phase A, sections 1–6 and 8–9. Phase B (fullscreen) gets its own plan once this phase is signed off and the source tree is in hand.

## Global Constraints

- **Nothing may get worse than engine c2:** frame rate and smoothness, sound, keyboard/mouse/focus, whether a game starts (through Steam and directly), the Steam client (sign-in, downloads, cloud sync, window, self-updates), D3DMetal and DXVK, saves.
- **Kamen does every login himself.** Nothing outside Cellar's folder is touched. Nothing is permanently deleted except Cellar's own temp files: use the Trash.
- **Automated tests are small, invisible and silent.** Every game Claude runs is muted (`--mute`), with the sound watchdog. ANIMAL WELL can't run muted, so only Kamen runs it.
- **Every visible run needs its own go-ahead from Kamen,** each time. Say what it will show and how long it takes. Several runs can be grouped into one ask only if he agrees at the time.
- **Downloads need Kamen's OK first,** with name, source and size. This covers the CrossOver source, and Homebrew packages if anything is installed on his Mac.
- **D3DMetal is never redistributed or uploaded,** and never copied out of Cellar's renderers folder. The engine loads it through `WINEDLLPATH_PREPEND`, as today.
- **Licences:** Cellar's own code and scripts stay MIT. Patches derived from Wine or CrossOver carry their licence (LGPL). Nothing is copied from the GPL-3.0 projects `diacunap/wine-cx-sikarugir`, Highball or `highball-engine`; they're credited where they taught us something.
- **Builds:** GitHub Actions on `kamenlevi/Cellar` (public, so free), or Kamen's Mac under a `peer lock share`. No paid compute.
- **Tests happen on an APFS clone of the Steam bottle,** never the real one, until sign-off. Only one of the two bottles runs at a time.
- **D3DMetal stays at Kamen's imported 3.0.**
- **Merge only on Kamen's "merge".** Work on branch `m4`.

## Review Focus

1. **A clone that shares files with the real bottle.** `cp -c` must clone, never hard-link. Writing in the clone must leave the real bottle byte-identical. Test: `aCloneIsIndependentOfItsSource` (Task 3).
2. **Two Steams at once.** Starting Steam in the clone while the real bottle's Steam runs (or the reverse) would give two clients on one account, and one gets "Session Replaced". Cellar refuses with a sentence. Test: `steamWontStartWhileAnotherBottlesSteamRuns` (Task 3).
3. **D3DMetal quietly not loading** on the new engine: the game runs on Wine's own d3d11 and looks fine but slow. The comparison treats renderer-not-loaded as a hard fail, whatever the fps. Test: `aCandidateWithoutItsRendererFailsWhateverItsFrameRate` (Task 4).
4. **One noisy run.** A single slow c2 run makes the spread huge, and a bad candidate passes. The spread is capped. Test: `aHugeBaselineSpreadIsCapped` (Task 4).
5. **The real bottle switching by accident.** `replaces` must not be set on the new engine until Kamen signs off (Task 6). An engine marked `isDefault: false` with no `replaces` must never move any bottle. Test: `anEngineThatReplacesNothingMovesNoBottle` (Task 3).

---

### Task 1: Downloads go-ahead, and the D3DMetal bridge gate

**Files:**
- Create: `docs/m4-spike.md`
- Modify: `docs/superpowers/specs/2026-10-17-cellar-design.md` (section 7: insert this milestone as M4, and renumber the old M4–M6 as M5–M7)

**Interfaces:**
- Produces: the ruling "base = CrossOver 25.1.1" or "base = 26.3", in `docs/m4-spike.md`. Tasks 2 onward read it.

- [ ] **Step 1: Ask Kamen for the downloads, listing each one.**
  - On his Mac: `crossover-sources-25.1.1.tar.gz` from codeweavers.com, 178,524,083 bytes.
  - On the GitHub runner, never his Mac: Homebrew `mingw-w64`, `bison`, `flex`, `pkgconf`, `freetype`, `gnutls`, `sdl2`, `molten-vk`, `gstreamer`; plus Wine Mono and Wine Gecko (the versions CrossOver 25.1.1 asks for).
  - Expected: his OK. Without it, stop.
- [ ] **Step 2: Download and unpack the source into `$TMPDIR/cellar-m4/src`.** Read `sources/wine/VERSION` and record it. Expected: `Wine version 10.0` (CrossOver 25.x).
- [ ] **Step 3: Compare the bridge, statically.**
  - CrossOver's side: `sources/wine/dlls/winemac.drv/d3dmetal.c` and the `CX_APPLEGPTK_LIBD3DSHARED_PATH` code in `sources/wine/dlls/ntdll`.
  - What D3DMetal 3.0 needs: `nm -gU` and `otool -L` on `~/Library/Application Support/Cellar/renderers/d3dmetal/3.0/external/libd3dshared.dylib`, read in place and never copied.
  - Today's engine: `strings` on c2's `ntdll.so` and `winemac.so`.
  - Expected: every symbol D3DMetal 3.0 calls into or exports for the bridge has a counterpart in 25.1.1's bridge with the same names.
- [ ] **Step 4: Write the ruling in `docs/m4-spike.md`.** Either "25.1.1's bridge matches D3DMetal 3.0", or "it doesn't: base moves to CrossOver 26.3". Ask Kamen first before downloading 26.3's source (149,054,023 bytes); the design says he is told before the base changes. Renumber the milestones in the Cellar design.
- [ ] **Step 5: Commit.**
```bash
git add docs/m4-spike.md docs/superpowers/specs/2026-10-17-cellar-design.md
git commit -m "M4: CrossOver bridge checked against D3DMetal 3.0; milestones renumbered"
```

### Task 2: The engine build: script, patches, CI, and the new checks

**Files:**
- Create: `scripts/build-engine.sh`
- Create: `engine/patches/crossover-25.1.1/0001-ntdll-winedllpath-prepend.patch`, `0002-winemac-no-made-up-mouseactivate.patch` (only if 25.1.1 lacks Wine b568eaac4a), `0003-no-crossover-username.patch`, and `README.md` (one line per patch: what it does, where it comes from, licence)
- Create: `.github/workflows/engine.yml`
- Modify: `scripts/package-engine.sh` (`--check` gains the new gates; the Sikarugir path stays as it is)
- Test: `Tests/CellarCoreTests/PackageEngineScriptTests.swift`

**Interfaces:**
- Consumes: Task 1's ruling (the base version).
- Produces:
  - The engine id `crossover-25.1.1-c1`.
  - The tarball `cellar-engine-crossover-25.1.1-c1.tar.xz`, laid out like today's:
    - `wine/bin/wine` is executable, and is a symlink if CrossOver's loader needs one;
    - `wine/lib/wine/x86_64-unix/*.so`;
    - `Frameworks/` holds the runtime libraries from `Template-1.0.11.tar.xz`, as in `package-engine.sh`;
    - `renderer/{dxvk,d9vk,dxmt}`;
    - `ENGINE.json` gains `"source": "crossover-sources-25.1.1.tar.gz"` and `"patches": [...]`.
  - `package-engine.sh --check <folder>` passes on it.

- [ ] **Step 1: Write the failing tests** in `PackageEngineScriptTests.swift`, in the file's existing style (`FakeEngine.makeFolder`, `check(_:)`):

```swift
@Test func checkRefusesAnEngineWithoutTheD3DMetalBridge() throws {
    // ntdll.so present but without CX_APPLEGPTK_LIBD3DSHARED_PATH
    #expect(result.code != 0); #expect(result.output.contains("D3DMetal bridge"))
}
@Test func checkRefusesAnEngineThatIgnoresWinedllpathPrepend() throws {
    // ntdll.so with the bridge string but without WINEDLLPATH_PREPEND
    #expect(result.code != 0); #expect(result.output.contains("WINEDLLPATH_PREPEND"))
}
@Test func checkRefusesASourceBuiltEngineWithoutMonoOrGecko() throws {
    // ENGINE.json id "crossover-…", ntdll.so with both strings, no wine/share/wine/{mono,gecko}
    #expect(result.code != 0); #expect(result.output.contains("Mono"))
}
@Test func checkPassesAnEngineWithBridgeAndPrepend() throws {
    // ntdll.so containing both strings
    #expect(result.code == 0)
}
```
  - Like the `winemac.so` check, the new checks apply only when `wine/lib/wine/x86_64-unix/ntdll.so` exists, so `checkPassesACleanEngine` keeps passing.
- [ ] **Step 2: Run them.** `swift test --filter PackageEngineScript`. Expected: the three refusal tests FAIL (exit code 0, no message).
- [ ] **Step 3: Add the two `grep -a` gates to `check()` in `scripts/package-engine.sh`.**
  - Messages: `ntdll.so has no D3DMetal bridge (CX_APPLEGPTK_LIBD3DSHARED_PATH)` and `ntdll.so ignores WINEDLLPATH_PREPEND`.
  - For engines whose id starts with `crossover-`, require `wine/share/wine/mono` and `wine/share/wine/gecko`. Message: `Wine Mono or Gecko is missing`.
  - Make the `winemac.so` focus-fix check apply only to Sikarugir engines: only when `ENGINE.json`'s id starts with `sikarugir-`. A source-built engine has no c2 byte edits; it gets the fix from source.
- [ ] **Step 4: Run them.** `swift test --filter PackageEngineScript`. Expected: all pass.
- [ ] **Step 5: Write the patches.**
  - `0001`: MacPorts' `game-porting-toolkit/files/1005-ntdll-d3dmetal-env.diff`, adapted to 25.1.1's `dlls/ntdll/unix/loader.c`. Its header names the source.
  - `0002`: Wine commit b568eaac4a, only if `grep -n 'HTMENU, WM_LBUTTONDOWN' sources/wine/dlls/winemac.drv/window.c` still finds the made-up click.
  - `0003`: undo CrossOver's change that names the Windows user `crossover`, so the Steam bottle's user stays `kamen`.
  - Each must apply with `patch -p1 --dry-run` against the unpacked tree.
- [ ] **Step 6: Write `scripts/build-engine.sh <workdir>`.**
  - It unpacks the source.
  - It applies `engine/patches/crossover-25.1.1/*.patch` in order.
  - It builds Wine as x86_64 with mingw-w64 GCC (`--with-mingw=x86_64-w64-mingw32-gcc`, not llvm-mingw), and with MoltenVK found at build time.
  - Its configure flags are `--enable-archs=i386,x86_64 --without-x --without-oss --disable-tests`, plus what MoltenVK needs. Do not pass `--with-opengl`.
  - It installs into `wine/`, adds `Frameworks/` and `renderer/` from the template exactly as `package-engine.sh` does, unpacks Mono and Gecko, and writes `ENGINE.json`.
  - It runs `package-engine.sh --check`, then tars the result and prints its SHA-256 and size.
- [ ] **Step 7: Write `.github/workflows/engine.yml`.**
  - It runs on `workflow_dispatch` only, on `macos-15-intel`.
  - It installs the Step 1 Homebrew packages and runs `scripts/build-engine.sh`.
  - It uploads the tarball as a workflow artifact. Nothing is published as a release from CI.
  - It caches ccache between runs.
- [ ] **Step 8: Build it.** Push branch `m4`, then `gh workflow run engine.yml --ref m4`, and watch with `gh run watch`.
  - Expected: success, the `--check` output ends `all dependencies resolve`, and the artifact is about 200–260 MB.
  - Each failure gets a fix in the script or a patch, and a ledger line.
  - If the runner's disk is too small, run the same script on Kamen's Mac under `peer lock share 90m --cpu 600 --gpu 0`.
- [ ] **Step 9: Commit,** with the patches, scripts and workflow. Release publishing waits until Task 6.

### Task 3: Steam on another bottle; bottle clones; engine choice per bottle

**Files:**
- Modify: `Sources/CellarCore/SteamStore.swift`, `Sources/CellarCore/Bottle.swift`, `Sources/CellarCore/CellarErrors.swift`, `Sources/cellar/Cellar.swift`
- Test: `Tests/CellarCoreTests/SteamStoreTests.swift`, `Tests/CellarCoreTests/BottleTests.swift`

**Interfaces:**
- Produces:
  - `SteamStore.init(…, bottle: String = SteamStore.bottleName, …)`.
    - Every use of `Self.bottleName` inside an instance becomes `self.bottle`.
    - `static let bottleName = "Steam"` stays as the default.
  - `BottleStore.clone(_ source: BottleName, to target: BottleName) throws -> BottleInfo`.
    - It uses `cp -c -R`, which is an APFS clone, and refuses an existing target.
    - It refuses while the source's wineserver runs, with `BottleError.inUse(String)`.
    - The new `bottle.json` has the target's name and the source's engine.
  - `BottleStore.setEngine(_ name: BottleName, to engineId: String) throws`.
    - The engine must already be installed; otherwise `EngineError.notInstalled`.
  - `SteamError.anotherSteamRuns(String)`.
    - `start()` throws it when any other bottle has `steam.exe` running.
    - Message: "Steam is already running in the \(other) bottle, and two Steams would sign each other out." Fix line: "Run: cellar steam stop (in that bottle), then try again."
  - CLI:
    - `cellar bottle clone <from> <to>`.
    - `cellar bottle engine <bottle> <engine-id>`.
    - The environment variable `CELLAR_STEAM_BOTTLE`, read in `steamStore()`, picks the bottle for `steam`, `play` and `check`. The default is `Steam`.

- [ ] **Step 1: Write the failing tests:**

```swift
@Test func steamInAnotherBottleUsesThatPrefix() async throws          // calls.txt lines show WINEPREFIX of bottles/Steam-m4
@Test func aCloneIsIndependentOfItsSource() throws                  // write a file in the clone's prefix; source's tree unchanged; clone's bottle.json name == "Steam-m4", engineId == source's
@Test func cloningOntoAnExistingBottleIsRefused() throws
@Test func setEngineNeedsTheEngineInstalled() throws                // EngineError.notInstalled("missing")
@Test func steamWontStartWhileAnotherBottlesSteamRuns() async throws // the other bottle's fake tasklist has steam.exe → SteamError.anotherSteamRuns("Steam")
@Test func anEngineThatReplacesNothingMovesNoBottle() async throws   // manifest: c2 default, "crossover-25.1.1-c1" isDefault false, no replaces → moveToNewerEngine == nil
@Test func anotherSteamRunsSaysWhatToDo()
```
- [ ] **Step 2: Run them.** `swift test --filter 'SteamStore|Bottle'`. Expected: compile errors for the missing API; then, as each piece lands, fails for the right reason.
- [ ] **Step 3: Implement the Interfaces above.**
  - "Another bottle's Steam runs": list the other bottles, and for each with a wineserver socket, run `tasklist` headless with the existing `commandTimeout`.
- [ ] **Step 4: Run the whole suite.** `swift test`. Expected: all pass (169 plus the new tests).
- [ ] **Step 5: Commit.**

### Task 4: The engine comparison

**Files:**
- Create: `Sources/CellarCore/EngineComparison.swift`
- Modify: `Sources/CellarCore/GameCheck.swift` (`CheckReport` becomes `Codable`, and the report is also written as `<name>.json` beside the `.md`), `Sources/cellar/Cellar.swift` (`cellar compare <baseline.json…> -- <candidate.json…>`)
- Test: `Tests/CellarCoreTests/EngineComparisonTests.swift`

**Interfaces:**
- Produces:
  - `struct EngineComparison { static func verdict(baseline: [CheckReport], candidate: [CheckReport]) -> [ComparisonFinding] }`. It is per game; the reports all belong to one game.
  - `struct ComparisonFinding: Equatable { var game: String; var what: String; var baseline: String; var candidate: String }`.
  - An empty array means "nothing worse".

**The rule, fixed:**
- A candidate is worse when any of these hold:
  - its renderer isn't loaded, or it stopped running, or its window wasn't seen, while every baseline run had it;
  - its average fps is below the lowest baseline average minus the spread;
  - its slowest moment is below the lowest baseline slowest moment minus the spread;
  - it has more hitches than the most in any baseline run, plus one;
  - its Wine errors contain a kind (the `err:<channel>:<function>` prefix) that no baseline run had.
- The spread is the baseline's highest average minus its lowest, capped at 5% of the lowest. Baseline runs are c2, at least two per game.

- [ ] **Step 1: Write the failing tests:**

```swift
@Test func anEqualCandidateIsNotWorse()                           // baseline 118,120; candidate 119 → []
@Test func aSlowerCandidateBeyondTheSpreadIsWorse()               // 118,120 (spread 2); candidate 115 → one finding "frame rate"
@Test func aCandidateWithoutItsRendererFailsWhateverItsFrameRate() // rendererLoaded false, fps 200 → finding "renderer"
@Test func aHugeBaselineSpreadIsCapped()                          // 60,120 → spread capped at 3; candidate 50 → worse
@Test func aNewKindOfWineErrorIsReported()                         // candidate adds err:d3d11:… → finding names it
@Test func reportsRoundTripThroughJSON()                           // CheckReport → JSON → CheckReport equal
```
- [ ] **Step 2: Run them.** `swift test --filter EngineComparison`. Expected: compile errors, then FAIL as the pieces land.
- [ ] **Step 3: Implement** `EngineComparison`, `CheckReport: Codable`, the JSON beside the markdown, and `cellar compare`. `cellar compare` prints one line per finding, or `nothing worse`, and exits 1 when anything is worse.
- [ ] **Step 4: Run the whole suite.** `swift test`. Expected: all pass.
- [ ] **Step 5: Commit.**

### Task 5: Compare on the real games

**Files:**
- Create: `docs/m4-compare.md` (one table per game: c2 runs, candidate runs, findings)
- Create: `scripts/m4-compare.sh` (runs the muted checks with the sound watchdog, as the M3 `checkrun.sh` did, for a list of games on one bottle)

**Interfaces:**
- Consumes: Task 2's tarball, installed locally with `cellar engine install` from the workflow artifact (the artifact is checked against its printed SHA-256). Task 3's clone, `setEngine` and `CELLAR_STEAM_BOTTLE`. Task 4's `cellar compare`.

- [ ] **Step 1: Prepare, nothing visible yet.**
  - With Steam stopped: `cellar bottle clone Steam Steam-m4`, then `cellar bottle engine Steam-m4 crossover-25.1.1-c1`.
- [ ] **Step 2: Ask Kamen for the c2 baseline runs.**
  - The runs: Chants of Sennaar, Outer Wilds, Journey, Leap Year and Rain World, two muted 2-minute checks each, about 25 minutes of windows on screen.
  - Group them into one ask only if he agrees.
  - Expected: his go-ahead. Then run `scripts/m4-compare.sh Steam`.
- [ ] **Step 3: Ask Kamen for the candidate runs.** The same games, one muted check each, now on `CELLAR_STEAM_BOTTLE=Steam-m4`, with Steam started in the clone (`CELLAR_STEAM_BOTTLE=Steam-m4 cellar steam start --mute`).
  - If Steam asks to sign in, stop: Kamen signs in himself.
  - Expected: his go-ahead, then the runs.
- [ ] **Step 4: Run `cellar compare` per game** and fill `docs/m4-compare.md`.
  - Expected: `nothing worse` for every game.
  - Each finding goes into the ledger and gets a fix: a patch in Task 2's set, a rebuild, then this task's Step 3 again for that game.
- [ ] **Step 5: The Steam client on the clone,** within Step 3's go-ahead or a new one:
  - signed in with the saved login;
  - a small download (Kamen picks it);
  - `AC Exit … Upload complete` in `cloud_log.txt` after a game quits;
  - its window comes back with `cellar steam`.
  - Record each in `docs/m4-compare.md`.
- [ ] **Step 6: Commit** `docs/m4-compare.md` and the script.

### Task 6: Kamen's play, sign-off, and the switch

**Files:**
- Create: `docs/m4a-signoff.md` (the table format of `docs/m3-signoff.md`)
- Modify: `Sources/CellarCore/Resources/engines.json`, `docs/engines.md`
- Test: `Tests/CellarCoreTests/EngineManifestTests.swift`

- [ ] **Step 1: Ask Kamen to play on the clone.**
  - Chants of Sennaar with sound, on `CELLAR_STEAM_BOTTLE=Steam-m4`, for as long as he likes. Include switching away and back (Cmd-Tab, Spotify).
  - ANIMAL WELL, which only he runs.
  - His words go in `docs/m4a-signoff.md`.
- [ ] **Step 2: On his sign-off, write the failing test:**

```swift
@Test func theSourceBuiltEngineReplacesC2() throws {
    let m = try EngineManifest.bundled()
    #expect(m.defaultEngine.id == "crossover-25.1.1-c1")
    #expect(m.replacement(for: "sikarugir-10.0_6-c2")?.id == "crossover-25.1.1-c1")
    #expect(m.replacement(for: "sikarugir-10.0_6-c1")?.id == "crossover-25.1.1-c1")
}
```
  Run `swift test --filter EngineManifest`. Expected: FAIL.
- [ ] **Step 3: Publish the engine.** This publishes a release on his GitHub, so ask Kamen first.
  - `gh release create engine-crossover-25.1.1-c1 <tarball>`, with notes giving the SHA-256, the source, the patches, and "D3DMetal is not included".
  - Pin it in `engines.json` as the default, with `replaces: ["sikarugir-10.0_6-c1", "sikarugir-10.0_6-c2"]`. c2 stays listed, `isDefault: false`.
  - Add an engine section to `docs/engines.md`.
- [ ] **Step 4: Run the whole suite.** `swift test`. Expected: all pass.
- [ ] **Step 5: Switch, keeping the way back.**
  - With Steam stopped: `cellar bottle clone Steam Steam-c2-backup`.
  - Then `cellar steam restart`. The fresh start moves the real bottle to the new engine.
  - Check `cellar steam status` says signed in. Check `bottle.json` names `crossover-25.1.1-c1`.
  - Move `Steam-m4` to the Trash.
- [ ] **Step 6: Commit and push.** Then the whole-branch review, then merge on Kamen's "merge".
