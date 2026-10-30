# Cellar M2 — First Game, All the Way (Outer Wilds) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:**
- `cellar play outer-wilds` takes Kamen straight into Outer Wilds, set up with the right DirectX→Metal translation.
- `cellar check outer-wilds` measures what can be measured and writes a report: frame pacing, window size, sound, renderer, errors and saves.
- Kamen plays the game and calls it the same as on Windows.

**Architecture:**
- Games stay in the shared `Steam` bottle (M1). Each game is started directly as its own Wine process, with its own renderer environment, while Steam runs beside it. Steam's own window therefore never loads a game's renderer.
- A game is described by a profile in a data file, `games.json`: Steam appid, exe, renderer, save folder.
- The check harness launches the game with Apple's Metal HUD logging on. It reads per-frame present intervals from the unified log, plus other facts from macOS (window list, power assertions, `lsof`), and writes `docs/checks/<game>-<date>.md`.

**Tech Stack:** As M1 (Swift 6.3, Swift Testing, ArgumentParser). macOS tools: `log stream`, `lsof`, `pmset -g assertions`, CoreGraphics window list. D3DMetal 3.0 (Kamen's import, `~/Library/Application Support/Cellar/renderers/d3dmetal/3.0`). DXVK from the engine's `renderer/dxvk`.

**Spec:** `docs/superpowers/specs/2026-10-17-cellar-design.md` (M2 in section 7, the bar and checklist in section 4, lessons in section 8). Prior milestones: `docs/m0-signoff.md`, `docs/m1-signoff.md`.

## Global Constraints

- All M0/M1 constraints still hold:
  - Kamen does every login himself;
  - nothing outside Cellar's root is touched;
  - nothing is permanently deleted except Cellar's own temp files;
  - small tests only;
  - automated tests are invisible and silent;
  - outward steps need Kamen's yes.
- **Anything that shows a game window or plays sound runs only when Kamen starts it** (his standing rule: test windows never come on top of his windows). That covers Task 1, every `cellar play` / `cellar check` on a real game, and the playtest. Unit tests use the fake engine.
- **Target:** Outer Wilds, Steam appid `753640`, Unity, D3D11 (spec section 3). ANIMAL WELL (`813230`, D3D12-only) is the regression game; it must also run through `cellar play`.
- **The bar** (spec section 4), for each game:
  - launches with one action and reaches gameplay;
  - visuals match reference footage;
  - music and sound effects play with no crackle;
  - cutscenes and video play;
  - keyboard and mouse work, and a DualSense works (rumble where the game has it);
  - holds its frame cap with no stutter;
  - saves persist and Steam Cloud syncs;
  - quit and relaunch are clean.
- **No getting around DRM** (spec section 2). A game started directly is still owned and verified by the running, signed-in Steam: `SteamAppId`/`SteamGameId` only tell Steamworks which game this is. If a game refuses to start that way, Cellar launches it through Steam (`steam.exe -applaunch`) instead, and never patches or emulates anything.
- **D3DMetal is never copied out of Cellar's renderers folder** and never redistributed.

## Review Focus

1. **Game not installed, or still downloading.** `cellar play` says so and names the fix ("Install it in Steam first"). It does not start Wine on a half-downloaded folder (Task 3).
2. **Steam not running or not signed in.** `cellar play` starts Steam (M1 `start()`), waits until it's signed in (up to 90 s), then launches the game. If sign-in never comes, it stops with a sentence, not a hang (Task 3).
3. **D3DMetal not imported** (a fresh Mac) and the profile asks for it. The fix line points at `cellar d3dmetal import`; there is no silent fallback to a renderer that shows a black screen (Task 2).
4. **Two `cellar play` of the same game.** The second one brings the running game forward instead of starting it twice (Task 3).
5. **The HUD log is missing** (the variable name changed between macOS versions, or the HUD was hidden). `cellar check` reports "no frame data" rather than a fake 0 fps or a crash (Task 4).

---

## File Structure

```
Sources/CellarCore/
  Renderer.swift          d3dmetal | dxvk | wined3d → environment additions
  GameProfile.swift       games.json model; lookup by id/appid/name
  Resources/games.json    Outer Wilds + ANIMAL WELL profiles
  SteamLibrary.swift      appmanifest_<appid>.acf → install state and folder
  GameStore.swift         play(): ensure Steam, launch the game directly; running?; bring forward
  GameCheck.swift         launch with HUD logging, collect, assess, write report
  FrameStats.swift        pure: metal-HUD log lines → frame intervals → fps, 1 % low, misses
  MacFacts.swift          window bounds (CoreGraphics), audio assertions (pmset), loaded libraries (lsof)
Sources/cellar/Cellar.swift   + `cellar play`, `cellar check`
Tests/CellarCoreTests/
  RendererTests.swift  GameProfileTests.swift  SteamLibraryTests.swift  GameStoreTests.swift
  FrameStatsTests.swift  MacFactsTests.swift  GameCheckTests.swift
  Fixtures/HUDLogFixtures.swift   lines captured in Task 1
docs/m2-spike.md          Task 1 answers
docs/checks/              reports written by `cellar check`
scripts/m2-checklist.md   Kamen's playtest
```

---

### Task 1: Spike with Kamen (about 15 minutes, nothing kept but notes)

Four questions decide the details of Tasks 2–4. Answer them on the real game before building on guesses. Outer Wilds must be fully downloaded first.

**Files:** create `docs/m2-spike.md` and throwaway `scripts/m2-spike.sh`. The script stays in the repo as a record but is not part of the product.

- [ ] **Step 1: Write `scripts/m2-spike.sh <variant>`.** It uses Kamen's real root and the shared `Steam` bottle, requires Steam running (`cellar steam` first), and starts `OuterWilds.exe` directly from its Steam folder. It runs `wine` from the installed engine with the M1 interactive environment plus:
  - all variants: `SteamAppId=753640 SteamGameId=753640 WINEDEBUG=fixme-all,err+all MTL_HUD_ENABLED=1 MTL_HUD_LOG_ENABLED=1 ROSETTA_ADVERTISE_AVX=1`;
  - `d3dmetal`: `WINEDLLPATH_PREPEND=<renderers>/d3dmetal/3.0/wine`, prepend `<renderers>/d3dmetal/3.0/external` to `DYLD_FALLBACK_LIBRARY_PATH`, set `DYLD_FALLBACK_FRAMEWORK_PATH=<renderers>/d3dmetal/3.0/external`, and add `d3d11,d3d12,d3d10core,dxgi=b` to `WINEDLLOVERRIDES`;
  - `dxvk`: `WINEDLLPATH_PREPEND=<engine>/renderer/dxvk/wine`, `d3d11,d3d10core,dxgi=n,b`;
  - `wined3d`: nothing extra (the baseline).

  In parallel it runs `log stream --style compact --predicate 'eventMessage CONTAINS "metal-HUD"' > .superpowers/spike-<variant>-hud.log` for 60 s. After 45 s it records `lsof -p <game pid> | grep -iE 'D3DMetal|d3dshared|dxvk|MoltenVK'` and `pmset -g assertions | grep -i audio` into `.superpowers/spike-<variant>-facts.txt`.
- [ ] **Step 2: Kamen runs `cellar steam`, then `scripts/m2-spike.sh d3dmetal`, then `dxvk`, then `wined3d`.** He quits the game between runs and says for each: menu reached? picture right? sound? Answers go into `docs/m2-spike.md`:
  1. **Direct launch:** does the game start and reach its menu with Steam running beside it (Steamworks OK, no relaunch through Steam)? If not, retry once with `steam.exe -applaunch 753640` and note it.
  2. **Renderers:** which load, by the `lsof` facts, and which show a correct picture?
  3. **HUD log:** the exact line format. Save 20 real lines into `Tests/CellarCoreTests/Fixtures/HUDLogFixtures.swift`, with the predicate and variable names that worked (`MTL_HUD_LOG_ENABLED`, or the older `MTL_HUD_LOGGING_ENABLED`).
  4. **Audio:** the exact `pmset -g assertions` line while the game plays sound.
- [ ] **Step 3: Commit.** `git commit -m "M2 spike: how Outer Wilds starts, which renderer, HUD log format"`. Every later task reads `docs/m2-spike.md`. Where an answer differs from this plan's assumption, the executor makes the smallest change and ledgers a Ruling.

### Task 2: Renderers and game profiles

**Files:** create `Renderer.swift`, `GameProfile.swift`, `Resources/games.json`, `RendererTests.swift` and `GameProfileTests.swift`; modify `CellarErrors.swift`.

**Interfaces:**

```swift
public enum Renderer: String, Codable, Sendable { case d3dmetal, dxvk, wined3d }
public enum RendererError: Error, Equatable { case d3dmetalNotImported }
public enum RendererSetup {
    /// Extra variables for a game process; merged over WineEnvironment.make(…, .interactive).
    public static func environment(_ r: Renderer, engine: InstalledEngine, d3dmetal: D3DMetalImport?, paths: CellarPaths,
                                   base: [String: String]) throws -> [String: String]
}
public struct GameProfile: Codable, Equatable, Sendable {
    public var id: String          // "outer-wilds"
    public var name: String        // "Outer Wilds"
    public var appid: Int          // 753640
    public var exe: String         // path inside the install folder: "OuterWilds.exe"
    public var renderer: Renderer
    public var saves: String?      // Windows path under the user profile, e.g. "AppData/LocalLow/Mobius Digital/Outer Wilds"
    public var launch: LaunchMode  // .direct (default) | .throughSteam
}
public enum LaunchMode: String, Codable, Sendable { case direct, throughSteam }
public struct GameProfiles { public static func bundled() throws -> [GameProfile]
                             public static func find(_ query: String, in: [GameProfile]) -> GameProfile? } // id, appid or case-insensitive name
```

- `games.json` starts with two entries:
  - Outer Wilds: renderer and launch mode as Task 1 decided (default assumption `d3dmetal`, `direct`), exe `OuterWilds.exe`;
  - ANIMAL WELL (`animal-well`, 813230): renderer `d3dmetal`, exe `Animal Well.exe`.
- `environment` returns exactly the per-variant additions from Task 1 Step 1, minus the HUD and debug variables, which belong to `GameCheck`. It also sets `WINEDLLOVERRIDES` by appending to the base value (keep `mscoree,mshtml=` and `winemenubuilder.exe=d`).
- `RendererError.d3dmetalNotImported` reads: "This game needs Apple's D3DMetal, which isn't imported yet." Its fix: `Run: cellar d3dmetal import ~/Downloads/<Evaluation environment for Windows games>.dmg`.

- [ ] **Step 1: Write the failing tests.**
  - `d3dmetalEnvironmentPointsAtTheImportedCopy`: `WINEDLLPATH_PREPEND` ends with `/renderers/d3dmetal/3.0/wine`; `DYLD_FALLBACK_LIBRARY_PATH` starts with `…/d3dmetal/3.0/external:`; `DYLD_FALLBACK_FRAMEWORK_PATH` is set; the overrides still contain `winemenubuilder.exe=d`.
  - `d3dmetalWithoutImportThrows`: `RendererError.d3dmetalNotImported`, with the exact fix line.
  - `dxvkEnvironmentUsesTheEngineCopy`.
  - `wined3dAddsNothing`: the result equals the base for those keys.
  - `bundledProfilesIncludeOuterWildsAndAnimalWell`: appids 753640 and 813230.
  - `findByIdAppidOrName`: `"outer-wilds"`, `"753640"`, `"outer wilds"` all find the same profile, and `"nope"` finds none.
- [ ] **Step 2: Run them.** `swift test -j 4 --filter "RendererTests|GameProfileTests"` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them.** → PASS, with the whole suite green.
- [ ] **Step 5: Commit.**

### Task 3: `cellar play`

**Files:** create `SteamLibrary.swift`, `GameStore.swift`, `SteamLibraryTests.swift` and `GameStoreTests.swift`; modify `Cellar.swift` and `CellarErrors.swift`.

**Interfaces:**

```swift
public enum InstallState: Equatable, Sendable { case installed(folder: URL), downloading, notInstalled }
public enum SteamLibrary {
    /// Reads steamapps/appmanifest_<appid>.acf: "StateFlags" 4 = fully installed; "installdir" names the folder in steamapps/common.
    public static func state(appid: Int, steamFolder: URL) -> InstallState
}
public enum GameError: Error, Equatable { case unknownGame(String), notInstalled(String), stillDownloading(String), steamNotSignedIn }
public enum PlayOutcome: Equatable, Sendable { case launched(pid: Int32), broughtForward }
public struct GameStore: Sendable {
    public init(paths: CellarPaths, steam: SteamStore, signInWait: Duration = .seconds(90), pollInterval: Duration = .seconds(2))
    public func play(_ profile: GameProfile, extraEnvironment: [String: String] = [:]) async throws -> PlayOutcome
    public func isRunning(_ profile: GameProfile) async throws -> Bool   // exe name (lowercased) in SteamStore.processes()
}
```

- `play` does, in order:
  1. check install state (`notInstalled` / `stillDownloading` errors name the game, with the fix "Install it in the Steam window first");
  2. if already running, run the exe again so Windows brings it forward, and return `.broughtForward`;
  3. `steam.start()` unless `processes()` shows `steam.exe` and `steamwebhelper.exe`;
  4. wait until `steam.status().health.signIn` is `.signedIn`, else `steamNotSignedIn`;
  5. spawn the game. For `.direct` that's `<install>/<exe>` with cwd the install folder, environment = interactive + `RendererSetup` + `SteamAppId`/`SteamGameId` + `ROSETTA_ADVERTISE_AVX=1` + `extraEnvironment`. For `.throughSteam` it's `steam.exe -no-cef-sandbox -applaunch <appid>`.
- `WineRunner.spawn` gains `environmentOverrides: [String: String] = [:]`, applied last.
- CLI: `cellar play <game>`. It prints `Starting Outer Wilds (D3DMetal)…`, or `Outer Wilds is already running; bringing it forward.`

- [ ] **Step 1: Write the failing tests** (fake engine rig as in M1, plus a `steamapps` folder with fixture manifests):
  - `installedManifestIsFound`, `downloadingManifestIsNotPlayable` (StateFlags 1026), `missingManifestIsNotInstalled`.
  - `playLaunchesTheExeDirectlyWithTheRendererAndAppId`: the recorded spawn has the exe path and cwd, `SteamAppId=753640` and `WINEDLLPATH_PREPEND`.
  - `playStartsSteamFirstWhenItIsNotRunning`.
  - `playStopsWithASentenceWhenSteamNeverSignsIn`: with `signInWait` at 1 s, `GameError.steamNotSignedIn` arrives in under 5 s.
  - `secondPlayBringsTheGameForward`.
  - `throughSteamProfileUsesApplaunch`.
- [ ] **Step 2: Run them.** → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them.** → PASS, with the suite green.
- [ ] **Step 5: Commit.**

### Task 4: `cellar check`, the measuring harness

**Files:** create `FrameStats.swift`, `MacFacts.swift`, `GameCheck.swift`, `FrameStatsTests.swift`, `MacFactsTests.swift`, `GameCheckTests.swift` and `Fixtures/HUDLogFixtures.swift` (from Task 1); modify `Cellar.swift`.

**Interfaces:**

```swift
public struct FrameStats: Equatable, Sendable {
    public var frames: Int, averageFPS: Double, onePercentLowFPS: Double, longestFrameMs: Double, stutters: Int  // stutter: present interval > 2× the median
    public static func parse(hudLog: String) -> [Double]            // present intervals in ms, from the line format in docs/m2-spike.md
    public static func summarize(_ intervalsMs: [Double]) -> FrameStats?   // nil when fewer than 30 frames
}
public enum MacFacts {
    public static func windows(pid: Int32) -> [CGRect]               // CGWindowListCopyWindowInfo, owner pid, on-screen only
    public static func audioPlaying(assertions: String, pid: Int32) -> Bool   // pure, over `pmset -g assertions` text (format from Task 1)
    public static func loadedLibraries(lsof: String) -> Set<String>   // pure: basenames from `lsof -p` text
}
public struct CheckReport: Sendable {
    public var game: GameProfile, renderer: Renderer, seconds: Int
    public var frames: FrameStats?, windowFillsScreen: Bool?, audio: Bool?, rendererLoaded: Bool?, wineErrors: [String], savesChanged: Bool?
    public func markdown() -> String          // sections in the order of the spec section 4 checklist; "no frame data" when frames == nil
    public var automaticVerdict: String       // "PASS (automatic part)" / "FAIL: <first failing item>"
}
public struct GameCheck: Sendable {
    public init(paths: CellarPaths, games: GameStore, steam: SteamStore)
    public func run(_ profile: GameProfile, seconds: Int) async throws -> CheckReport
}
```

- `run` does, in order:
  - starts `log stream` (predicate from Task 1);
  - `GameStore.play(profile, extraEnvironment: HUD variables)`;
  - samples windows, audio and `lsof` at 30 s and at the end;
  - collects `err:` lines from the game's Wine log (deduplicated, first 20);
  - compares save-folder modification times before and after;
  - stops `log stream`.

  It never quits the game: Kamen keeps playing.
- Pass rules:
  - `averageFPS` ≥ 0.95 × the display's refresh rate, or ≥ 0.95 × the game's cap when Task 1 shows one;
  - `stutters` ≤ 1 per minute;
  - the window covers the screen (or the game's windowed size if set);
  - audio is playing;
  - the renderer is loaded (`D3DMetal` in `loadedLibraries` for d3dmetal);
  - no Wine `err:` lines that also appear in a crash.
- CLI: `cellar check <game> [--seconds 120]`. It prints the report path and the verdict.

- [ ] **Step 1: Write the failing tests:**
  - `parsesRealHUDLines`, against the Task 1 fixture: interval count = fixture count;
  - `steady60fps`: 600 × 16.67 ms gives average ≈ 60 and 0 stutters;
  - `oneHitchIsCounted`;
  - `tooFewFramesIsNoData`;
  - `audioAssertionForThisPidOnly`;
  - `librariesAreBasenames`;
  - `reportSaysNoFrameDataInsteadOfZero`;
  - `verdictNamesTheFirstFailure`.
- [ ] **Step 2: Run them.** → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them.** → PASS, with the suite green.
- [ ] **Step 5: Commit.**

### Task 5: Kamen plays (sign-off)

**Files:** create `scripts/m2-checklist.md` and `docs/m2-signoff.md`.

- [ ] **Step 1: Write the checklist.** Kamen's steps:
  1. `cellar play outer-wilds`. The game reaches its menu with no extra steps.
  2. `cellar check outer-wilds --seconds 120` while flying around the first area. The automatic part passes; the report is in `docs/checks/`.
  3. Compare one scene with reference footage (the opening campfire and the first launch), for picture and sound.
  4. The opening cutscene and the in-game projection videos play.
  5. Keyboard and mouse. Then the DualSense: menus, flight, rumble if the game has it.
  6. Play until the game saves (it saves at the end of a loop), quit from the game menu, then `cellar play outer-wilds` again: the save is there. Check that `cloud_log.txt` shows an upload.
  7. `cellar play animal-well` reaches gameplay (the regression check).
  8. Kamen's call: "the same as Windows?" If yes, M2 is done. Anything wrong becomes a profile change or a fix, then rerun that step.
- [ ] **Step 2: Commit and push `m2`.** Merge only on Kamen's "merge".
