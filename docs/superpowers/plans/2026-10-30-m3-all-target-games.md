# Cellar M3 — All Target Games Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:**
- `cellar play` takes Kamen into each of the four remaining targets:
  - Outer Wilds (moved here from M2);
  - Journey;
  - Chants of Sennaar;
  - Leap Year.
- Each passes the section 4 checklist and Kamen signs it off.
- Rain World and ANIMAL WELL keep working.

**Architecture:**
- Nothing new in the overall shape. Games stay in the shared `Steam` bottle. Cellar starts Steam with D3DMetal, and Steam launches each game (M2: cloud saves sync).
- What a game needs is data in `games.json`, or a rule every game gets. Never a one-off branch in code (spec, M3).
- Two rules come from what M2 and the research taught:
  - Cellar reads the exe itself, to learn whether it is 64-bit and which DirectX it imports. D3DMetal ships 64-bit DLLs only.
  - A first launch that runs Steam's installers counts as Steam working, not as Steam ignoring the launch.

**Tech Stack:** As M2 (Swift 6.3, Swift Testing, ArgumentParser, D3DMetal 3.0, the engine's DXVK, `cellar check`).

**Spec:** `docs/superpowers/specs/2026-10-17-cellar-design.md`: M3 in section 7, the games in section 3, the bar in section 4. Prior: `docs/m2-signoff.md`, `docs/m2-spike.md`. Research notes, 2026-10-30, with sources: section "What we know" below.

## Global Constraints

- All M0–M2 constraints hold:
  - Kamen does every login himself.
  - Nothing outside Cellar's root is touched, and nothing is permanently deleted except Cellar's own temp files.
  - Small tests only. Automated tests are invisible and silent.
  - Merge only on Kamen's "merge".
  - D3DMetal is never copied out of Cellar's renderers folder.
  - No getting around DRM.
- **Downloads are Kamen's:** he presses Install in the Steam window (about 16 GB in all, Task 3).
- **Sound:** a game run by Claude is **always muted**, with `--mute` or a muted Steam (`cellar steam --mute`).
  - It is guarded by the watchdog: kill the game if `pmset -g assertions` shows an output assertion "Created for PID: <game>".
  - A game that crashes without a sound device (as ANIMAL WELL does) is run only by Kamen.
  - Claude's runs show a window. They happen only after Kamen's OK for that session.
- **Fair use of the Mac:** frame-rate measurements run under `peer lock quiet --queue 25m "<why>"`, and `peer unlock` right after.
- **Controller:** deferred by Kamen on 2026-10-30 ("we will deal with later if I need it"). DualSense steps stay in the checklist, marked optional.
- **Targets:**

| id | Name | appid | exe (from SteamCMD) | Saves (under the Windows profile) | Cloud | fps |
|---|---|---|---|---|---|---|
| `outer-wilds` | Outer Wilds | 753640 | `OuterWilds.exe` | `AppData/LocalLow/Mobius Digital/Outer Wilds` | yes | 60 (physics runs at 60) |
| `journey` | Journey | 638230 | `Journey.exe` | `AppData/Local/Annapurna Interactive/Journey` | yes | nil (supports 120) |
| `chants-of-sennaar` | Chants of Sennaar | 1931770 | `Chants Of Sennaar.exe` | `AppData/LocalLow/Rundisc/Chants Of Sennaar` | yes | nil (supports 120+) |
| `leap-year` | Leap Year | 2951770 | `Leap Year.exe` | unknown until Task 3 | **no** | unknown until Task 3 |

## What we know (research, 2026-10-30)

- **Outer Wilds:** Unity 2019.4, 64-bit D3D11, 11.65 GB. ProtonDB Platinum (401 reports).
  - On a Mac with DXVK, characters are invisible. The fix is the launch option `-disable-gpu-skinning` (AppleGamingWiki).
  - A user report says D3DMetal runs it fine.
- **Journey:** PhyreEngine, 64-bit D3D11, 3.6 GB. Comes with FMOD sound, Sony's own DualShock library, and Epic Online Services for multiplayer. ProtonDB Platinum (116).
  - Reported: a crash at one spot that went away with fsync/esync off; a black screen after the logos; and a white-screen freeze in the final animation.
  - Cloth stutters above 30 fps unless "Cloth Interpolation" is on, and the game can crash above 144 fps.
- **Chants of Sennaar:** Unity 2021.3 (Mono), Wwise sound, 0.6 GB, no video files. ProtonDB Platinum (53); Deck Verified "No changes needed".
- **Leap Year:** GameMaker, 39 MB, no Steam Cloud. The store says "DirectX 10", but GameMaker draws through D3D11, so the exe's imports decide. ProtonDB Gold (14).
- **Renderers:** D3DMetal 3.0 ships `d3d10.dll`, `d3d11.dll`, `d3d12.dll` and `dxgi.dll`, for **x86_64 only**. DXVK ships both 32- and 64-bit.

## Review Focus

1. **A first launch runs Steam's installers** (DirectX June 2010, VC++), which can take minutes. M2's launch fix waits 45 s and then restarts Steam. It must not kill Steam in the middle of an install (Task 2), and it lands before the first real launch (Task 3).
2. **A 32-bit exe with `renderer: d3dmetal`** would quietly get Wine's own d3d11 and look wrong or slow. `cellar play` refuses it with a sentence naming DXVK (Tasks 1 and 2).
3. **Steam says "Install" but the files aren't all there** (a download paused at 99 %). The M2 rule, "still downloading", holds for the new games too, because their manifests are read the same way. No new test needed: covered by `SteamLibraryTests`.
4. **A game that needs a launch option** (Outer Wilds on DXVK). The option must reach the game both through Steam and in a direct start; `-applaunch <appid> <args…>` carries it (Task 4).
5. **Another game is already running when a new one is asked for.** The M2 rule doesn't restart Steam in that case. The new game still launches, and the setup rule (1) must not take the old game for an installer (Task 2).

---

## File Structure

```
Sources/CellarCore/
  ExeFacts.swift          new: PE header → 64-bit?, imported DLLs, DirectX version
  GameProfile.swift       + arguments: [String] (Task 4)
  Resources/games.json    + journey, chants-of-sennaar, leap-year; outer-wilds fps 60
  GameStore.swift         + bitness check, setup-aware wait, `starting` callback
  Renderer.swift          + RendererError.d3dmetalNeeds64Bit
  CellarErrors.swift      messages
Sources/cellar/Cellar.swift   play prints "Starting…" only once the game can start
Tests/CellarCoreTests/
  ExeFactsTests.swift  Fixtures/PEFixture.swift   GameStoreTests.swift  GameProfileTests.swift
docs/m3-spike.md  docs/checks/<game>-*.md  scripts/m3-checklist.md  docs/m3-signoff.md
```

---

### Task 1: Read the exe, and profiles for the new games

**Files:**
- Create: `Sources/CellarCore/ExeFacts.swift`, `Tests/CellarCoreTests/ExeFactsTests.swift`, `Tests/CellarCoreTests/Fixtures/PEFixture.swift`.
- Modify: `Resources/games.json`, `GameProfileTests.swift`.

**Interfaces:**
- Produces:
  - `public struct ExeFacts: Equatable, Sendable { public var is64Bit: Bool; public var imports: Set<String> }`. Imports are lowercased DLL names.
  - `public var directX: Int?`: 12, 11, 10 or 9, from the highest of `d3d12.dll` / `d3d11.dll` / `d3d10*.dll` / `d3d9.dll`; nil when it imports none of them.
  - `public static func read(_ exe: URL) throws -> ExeFacts`, which throws `ExeFactsError.notAWindowsProgram` for anything without `MZ` + `PE\0\0`.
- Test helper: `PEFixture.make(machine: UInt16, imports: [String]) -> Data`, a minimal valid PE with one section holding an import directory.

- [ ] **Step 1: Write the failing tests:**
  - `sixtyFourBitD3D11GameIsRead`: `make(machine: 0x8664, imports: ["KERNEL32.dll", "d3d11.dll", "dxgi.dll"])` gives `is64Bit`, with imports containing `"d3d11.dll"` and `directX == 11`.
  - `thirtyTwoBitIsNotSixtyFour`: machine `0x14c` → `!is64Bit`.
  - `d3d10ImportMeansDirectX10`: imports `["d3d10_1.dll"]` → 10.
  - `noDirectXImportIsNil`: `["user32.dll"]` → nil. Unity's player loads d3d11 at run time, not through imports, so nil is a real answer.
  - `textFileIsNotAWindowsProgram`: throws.
  - `GameProfileTests.everyTargetGameHasAProfile`: `find` resolves `journey`, `638230`, `chants of sennaar`, `leap-year`, with the table's exe and saves; `outer-wilds` has `fps == 60`.
- [ ] **Step 2: Run them.** `swift test -j 4 --filter "ExeFactsTests|GameProfileTests"` → FAIL.
- [ ] **Step 3: Implement.** The import names are the RVAs in import directory entry 1 (data directory index 1), mapped through the section table. The optional header magic is `0x20b` for PE32+, `0x10b` for PE32. Read with `Data` and bounds checks: a truncated file throws, it never traps. Add the three profiles from the table (`renderer: d3dmetal`; Leap Year `saves` omitted).
- [ ] **Step 4: Run them.** → PASS, with the suite green.
- [ ] **Step 5: Commit.** `git commit -m "Read a game's exe: 64-bit and DirectX imports; profiles for Journey, Chants of Sennaar, Leap Year"`

### Task 2: `cellar play` knows installers, 32-bit exes, and when to say "Starting…"

**Files:** modify `GameStore.swift`, `Renderer.swift`, `CellarErrors.swift`, `Cellar.swift` and `GameStoreTests.swift`.

**Interfaces:**
- Consumes: `ExeFacts.read` (Task 1).
- Produces:
  - `play(_:extraEnvironment:muted:starting:)`, where `starting: @Sendable () -> Void = {}` is called once every check has passed, right before Wine starts anything.
  - `RendererError.d3dmetalNeeds64Bit(String)`.
  - `GameStore(…, setupWait: Duration = .seconds(600))`.

Rules:
- **Bitness:** a `d3dmetal` profile whose exe reads as 32-bit throws `d3dmetalNeeds64Bit(name)`. The message: "<name> is a 32-bit program, and D3DMetal only runs 64-bit ones." The fix line: "Set its renderer to dxvk in games.json." An exe that can't be read is not refused: a launcher stub may not be a PE file Cellar understands.
- **Installers:** record the bottle's processes just before `-applaunch`. While waiting for the game, a process that wasn't there before, isn't a Wine system process, isn't the game and doesn't start with `steam` means Steam is installing something. While any such process runs, the deadline moves out to `setupWait` from the ask; Steam is never restarted during it. The rule is generic, not a list of installer names.
- **"Starting…"** prints from `starting`, so a game that isn't installed gets only the error (M2's leftover).

- [ ] **Step 1: Write the failing tests** (the M2 `GameRig`, with its fake `-applaunch`; add a `slowSetup` marker). With the marker, the fake lists `"DXSETUP.exe"` at once and adds the game 3 s later, with `launchWait` 2 s and `setupWait` 10 s:
  - `firstLaunchInstallersAreWaitedForNotRestarted`: `.launched` with `restartedSteam == false`; no `-shutdown` line.
  - `aGameAlreadyRunningIsNotTakenForAnInstaller`: `"Animal Well.exe"` in the tasklist before the ask, and Steam `stale`. Expect `steamIgnoredLaunchBeside` after `launchWait`, not after `setupWait` (elapsed < 8 s).
  - `thirtyTwoBitExeIsRefusedForD3DMetal`: the rig writes `PEFixture.make(machine: 0x14c, imports: ["d3d11.dll"])` as `OuterWilds.exe`. Expect `RendererError.d3dmetalNeeds64Bit("Outer Wilds")` and no Wine call naming the exe.
  - `unreadableExeIsStillStarted`: the rig's existing two-byte `"MZ"` exe still launches (all M2 tests keep passing).
  - `startingIsAnnouncedOnlyForAGameThatCanStart`: an uninstalled game never calls `starting`; an installed one calls it exactly once.
- [ ] **Step 2: Run them.** `swift test -j 4 --filter GameStoreTests` → FAIL.
- [ ] **Step 3: Implement**, and pass `starting: { print("Starting \(profile.name) (\(profile.renderer.displayName))…") }` from `Play`.
- [ ] **Step 4: Run them.** → PASS, with the suite green.
- [ ] **Step 5: Commit.** `git commit -m "cellar play: wait out Steam's first-run installers, refuse 32-bit exes on D3DMetal, announce only a game that can start"`

### Task 3: Kamen downloads; first look at each game (a spike: notes and data, no product code)

**Files:** create `docs/m3-spike.md`; modify `Resources/games.json` with what the spike finds.

- [ ] **Step 1: Kamen installs the four games** in the Steam window (`cellar steam`): Outer Wilds 11.65 GB, Journey 3.6 GB, Chants of Sennaar 0.6 GB, Leap Year 39 MB. Wait for `StateFlags 4` in each `appmanifest_<appid>.acf`.
- [ ] **Step 2: For each game, record in `docs/m3-spike.md`:**
  - the real exe name (the table's names come from SteamCMD and must be checked);
  - `ExeFacts` (a throwaway `swift run` snippet or a test reading the real file): 64-bit? which DirectX?;
  - the save folder as it appears after the first run. For Leap Year, look under `AppData/Local`.
- [ ] **Step 3: First launch, Claude, muted, with Kamen's OK for the session.**
  - Run `cellar steam --mute` with the watchdog running, then `cellar play <id> --mute`.
  - Record:
    - whether Steam ran installers first (a process list every 2 s for the first 3 minutes: names and how long they lived);
    - whether it reached the menu (a silent `screencapture -x -l <window>` of the game window);
    - the renderer in `lsof`;
    - whether the window fills the screen.
  - A game that dies without a sound device goes on Kamen's list instead. Note that and move on.
- [ ] **Step 4: If a game fails on D3DMetal, try DXVK once** (`scripts/m2-spike.sh dxvk`-style direct start, muted). Record which renderer works and any launch option the research names (Outer Wilds: `-disable-gpu-skinning` on DXVK).
- [ ] **Step 5: Correct the profiles** (exe, saves, renderer, fps) and commit. `git commit -m "M3 spike: what each game needs on first launch"`.
  - Where an answer breaks this plan's assumptions, make the smallest change and ledger a Ruling.
  - Task 4 is skipped if no game needs a launch option.

### Task 4 (only if Task 3 found one): launch options in the profile

**Files:** modify `GameProfile.swift`, `GameStore.swift`, `games.json`, `GameProfileTests.swift` and `GameStoreTests.swift`.

**Interfaces:** `GameProfile.arguments: [String]`, default `[]`, decoded with `decodeIfPresent`.

- [ ] **Step 1: Write the failing tests:**
  - `argumentsReachTheGameThroughSteam`: the fake's call line contains `-applaunch 753640 -disable-gpu-skinning`.
  - `argumentsReachADirectStart`: the call line contains `OuterWilds.exe -disable-gpu-skinning`.
  - `profilesWithoutArgumentsDecode`: the bundled JSON has no `arguments` key and gives `[]`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement**, appending `profile.arguments` after `-applaunch <appid>` and after the exe path. **Step 4: Run** → PASS.
- [ ] **Step 5: Commit.** `git commit -m "Game profiles carry launch options"`

### Task 5: Claude's muted checks, then Kamen plays each game (sign-off)

**Files:** create `scripts/m3-checklist.md`, `docs/checks/<game>-<date>.md` (copied from `~/Library/Logs/Cellar/checks/`) and `docs/m3-signoff.md`.

- [ ] **Step 1: Claude's muted check per game.** For each game whose profile says D3DMetal and that survives `--mute`:
  - Take `peer lock quiet --queue 25m "Cellar M3 check <game>"`.
  - With the watchdog running, run `cellar check <id> --seconds 120 --mute`, sending keys with CGEvent `postToPid` only to get past the title screen.
  - Then `peer unlock`.
  - Copy each report into `docs/checks/`. A FAIL becomes a profile change (fps, renderer, arguments) and a re-check, never a code special case. Also re-run `cellar check rain-world --mute` as the regression.
- [ ] **Step 2: Write `scripts/m3-checklist.md`.** It holds M2's 11 steps, once per game, with these notes:
  - **Outer Wilds:** play until the first loop ends (22 minutes) or quit after a campfire; the save is kept per loop. 60 fps target; 120 needs the game's `PhysicsRate` file and is not a goal.
  - **Journey:** turn on "Cloth Interpolation" if the scarf stutters. Say whether the logos are followed by a black screen. Online play is out of scope.
  - **Chants of Sennaar:** check that text and glyphs render (font issues are the usual Wine failure).
  - **Leap Year:** no Steam Cloud, so step 8 is replaced by "the save survives quit and relaunch".
  - **Everywhere:** DualSense optional (deferred). ANIMAL WELL step 10, by Kamen; it needs sound.
- [ ] **Step 3: Kamen plays each game**, with sound, at his pace. Each finding becomes a profile change or a fix (back to the task that owns it), and that game's steps run again.
- [ ] **Step 4: Write `docs/m3-signoff.md`**, one table per game as in `docs/m2-signoff.md`, quoting Kamen's call. Commit and push `m3`. Merge only on Kamen's "merge".
