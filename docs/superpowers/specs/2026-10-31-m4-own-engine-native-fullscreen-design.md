# M4: Cellar's own engine, and real macOS fullscreen

Design, 2026-10-31. Builds on `docs/superpowers/specs/2026-10-17-cellar-design.md` (the Cellar design) and M3 (`docs/m3-signoff.md`).

## 1. What this is, and why

When Kamen plays Chants of Sennaar in Cellar, the game covers the screen, but it isn't macOS fullscreen. It is a borderless window the size of the screen, sitting on his normal desktop. Wine hides the menu bar and Dock while the game is in front. When he switches to Claude, the game window stays behind it, so black shows around the Dock and at the top where his wallpaper should be. The game has no desktop of its own, and it appears nowhere in Mission Control as one.

Kamen wants Cellar games to behave like a native Mac game. His example is Celeste (2026-10-31):

> "i picture it, like if i play a game which is native on mac. … when i play celeste, the game opens in a second desktop. i want it like that. immediately opened in a second desktop with every property of a desktop. if i cmd tab, i go to the other desktop and back again. when i am in desktop 1, my game isnt there."

Wine's Mac driver can't do this today. It gives macOS fullscreen only to windows with a title bar that can be resized, and almost every game opens borderless. Chants ignores every "start in a window" switch (tested 2026-10-31). The fix has to go into the Mac driver itself: about 30–60 lines in `dlls/winemac.drv/cocoa_window.m`.

Cellar's engine today (`sikarugir-10.0_6-c2`) is Sikarugir's binary build of Wine 10.0. Its source isn't public, so its Mac driver can only take small byte edits (c2's focus fix), not new code. **So Cellar first builds its own engine from public source, then adds fullscreen to it.**

## 2. Goals

1. **Every game Cellar starts opens straight into its own macOS desktop (Space),** like Celeste. No click, no green button, nothing for Kamen to do. "Every game" is Kamen's confirmation of Claude's guess.
2. **That desktop has every property of a normal fullscreen app's desktop:**
   - It shows in Mission Control as its own tile named after the game.
   - Cmd-Tab and trackpad swipes move between it and the other desktops.
   - Desktop 1 has no trace of the game: no black window, nothing around the Dock.
   - The menu bar and Dock are hidden inside the game's desktop, as macOS does for fullscreen apps (Kamen confirmed this guess).
   - When the game quits, its desktop closes.
3. **The picture:**
   - It sits below the camera notch, with the thin black strip at the top that every native fullscreen app has. Kamen: "it should be like celeste".
   - A game that supports 16:10 fills the area below the notch.
   - A 16:9 game shows black bars above and below. Kamen: "if a game is like that black bars are perfectly fine. only if a game is optimised for 16:10, should it be in 16:10".
4. **Keys and mouse work the moment Kamen comes back to the game.** Engine c2 already does this; the new engine must too.
5. **Cellar builds its own engine from public source,** reproducibly, and publishes it on `kamenlevi/Cellar` like every engine so far.

## 3. Anti-goals

**Nothing may get worse.** Kamen: "everything is bad. we mustnt degrade anything by doing this." Compared with engine c2, on every game Cellar knows, none of these may get worse:
- frame rate and smoothness;
- sound;
- keyboard, mouse, and focus after switching away and back;
- whether a game starts at all, through Steam and directly;
- the Windows Steam client: sign-in, downloads, cloud sync, its window, self-updates;
- D3DMetal and DXVK both working;
- saves.

A new engine that fullscreens perfectly but loses any of these is a failure.

## 4. Constraints

All earlier constraints still hold:
- Kamen does every login himself.
- Nothing outside Cellar's folder is touched, and nothing is permanently deleted except Cellar's own temp files.
- Automated tests are small, invisible and silent.
- Every game Claude runs is muted (`--mute`), with the sound watchdog.
- Merge only on Kamen's "merge".

New for this milestone:
- **Downloads need Kamen's OK, with name, source and size.** For example, CrossOver's source archive is 178,524,083 bytes, and the libraries an engine bundles have to come from somewhere too. Ask before the first download, listing everything.
- **D3DMetal is never redistributed or uploaded.** It stays imported from Kamen's own Game Porting Toolkit download. The engine must load it from there, as today, through `WINEDLLPATH_PREPEND`.
- **Licences:**
  - Wine and CrossOver sources are LGPL/GPL. Patch files derived from them carry that licence, which is fine.
  - Cellar's own code and build scripts stay MIT. So no script is copied from the GPL-3.0 projects this design learned from (`diacunap/wine-cx-sikarugir`, Highball and `highball-engine`). Their write-ups can be read and credited; their code can't be used.
- **Build machines:** GitHub Actions on `kamenlevi/Cellar`, which is public, so the standard macOS runners are free. Building on Kamen's Mac is also allowed, but it has to share the machine politely with the other sessions (peer locks). No paid compute.
- **Every visible run needs its own go-ahead from Kamen, each time.** This covers games and Cellar's own silent test window alike. Kamen chose "ask each time" (2026-10-31) over one go-ahead per work session. Fullscreen runs are visible by nature, since the screen switches desktops.
  - Phase B's logic is built and tested without a screen as far as possible.
  - Each visible run is asked for on its own, saying what it will show and for how long. Several can be grouped into one ask only if Kamen agrees at the time.

## 5. What was decided

### By Kamen
- Games open straight into their own desktop, every game, like Celeste (section 2).
- Below the notch; bars only for 16:9 games (section 2).
- No degradation of any kind (section 3).
- Build Cellar's own engine to get there: "my vote is to make the real macos fullscreen", after being told it needs Cellar's own engine.

### By Claude, for Kamen to check
- **Two phases, each with its own sign-off.**
  - **Phase A** builds an engine with *no* fullscreen change. It must match c2 on everything in section 3.
  - **Phase B** adds fullscreen on top of A's engine.
  - This way any regression is the engine's or the fullscreen change's, never a mix of both.
- **Base: CodeWeavers' CrossOver 25.1.1 source.**
  - It's Wine 10.0, the same base as today. Sikarugir's build appears to be Wine 10.0 plus a hand-picked set of CrossOver changes, including the D3DMetal bridge (research, 2026-10-31). CrossOver 25.1.1 is the only public tree on that base with those pieces.
  - **Fallback:** CrossOver 26.3 (Wine 11.0). Three public build recipes exist for it, and it ships for D3DMetal 3.0. But it's a bigger jump with more behaviour change, so use it only if 25.1.1 can't be built or can't match c2.
- **Patches on the base,** each its own file with a header saying where it comes from:
  1. `WINEDLLPATH_PREPEND`: the small ntdll patch that lets the engine load Kamen's imported D3DMetal. It comes from MacPorts' `game-porting-toolkit` port (`1005-ntdll-d3dmetal-env.diff`). Without it, games quietly fall back to Wine's own slow d3d11.
  2. The focus fix (Wine b568eaac4a), if 25.1.1 doesn't already have it. CrossOver's hack 18896, the other half of c2's fix, is already in CrossOver.
  3. Undo CrossOver's change that renames the Windows user to "crossover". The Steam bottle's user is `kamen`, and it must stay that way.
  4. Whatever else matching c2 turns out to need. Each one is found by a failing comparison, not added in advance. Candidates from the research: Highball's retina screen-size patch, and Sikarugir's msync.
  5. Phase B only: the native-fullscreen change.
- **Toolchain:**
  - mingw-w64 GCC, not llvm-mingw: an llvm-built `kernelbase.dll` is reported to stall Steam's login.
  - x86_64 cross-build: an arm64-host build of CrossOver's `cocoa_window.m` is reported to fail.
- **The new engine is a normal Cellar engine.** It is published, pinned in `engines.json` by URL, SHA-256 and size, and built by a script in `scripts/`.
- **Switching is reversible and on Kamen's word:**
  - c2 stays installed and pinned.
  - The new engine replaces c2 (`replaces` in `engines.json`) only after its phase is signed off.
  - Until then, Cellar can run the Steam bottle on either engine, so tests can compare the two on the same games and saves.
  - Going back means pointing the bottle at c2 again.
- **Tests run on a copy of the Steam bottle, never the real one,** until a phase is signed off.
  - The copy is an APFS clone (`cp -c`), so it costs almost no disk until something changes.
  - A different engine's first start rewrites parts of a prefix (its Wine version differs). Pointing the real bottle back at c2 afterwards might not restore it exactly, and the real bottle holds Kamen's signed-in Steam and his saves.
  - The clone carries Steam's saved login and the installed games. Saves made while testing travel through Steam Cloud, which syncs on every game exit.
  - Only one of the two bottles runs at a time.
  - The real bottle moves to the new engine only after sign-off, and a clone of it is kept until the next milestone as the way back.
- **D3DMetal stays at the version Kamen imported (3.0).** No new Apple download.
  - The first gate, before the full engine build, is a cheap check that 25.1.1's D3DMetal bridge loads 3.0. Sikarugir's Wine 10.0 build does today, with CrossOver's bridge, which suggests it will.
  - If it doesn't, the base moves to CrossOver 26.3, which ships for D3DMetal 3.0. Kamen is told before the base changes.
- **A per-game opt-out:** `fullscreen` in `games.json`, `native` by default, `off` keeping today's behaviour. It's there in case a game misbehaves in its own desktop; no game uses it at the start.
- **Milestone numbering.** This becomes M4. The old M4–M6 (automatic for new games, built to last, the app) move to M5–M7. M5's "engine upgrades on Kamen's terms" overlaps with this milestone's switching rule, so phase A's switch counts as a first instance of it.

## 6. How "no degradation" is checked

### Phase A: the new engine against c2, before anything switches
- **Engine gates, enforced by `scripts/package-engine.sh --check`:**
  - every `@rpath` library resolves;
  - no Apple Game Porting Toolkit file is inside;
  - the D3DMetal bridge and `WINEDLLPATH_PREPEND` support are present in the binaries;
  - Mono and Gecko are bundled, as today.
- **Same games, both engines:** c2 on the real bottle, the new engine on its clone (section 5). Every game Cellar knows runs on both, muted, with `cellar check`, and the reports are compared:
  - frame rate, slowest moment and hitches;
  - the renderer that actually loaded: D3DMetal vs Wine's own d3d11 is a hard fail;
  - the Wine errors;
  - whether the window appeared.
  - The games: Chants of Sennaar, Outer Wilds, Journey, Leap Year and Rain World. ANIMAL WELL can't run muted, so Kamen runs it.
- **The Steam client:** sign-in with the saved login (Kamen signs in himself if it asks), a small download, a cloud sync on a game's exit, and its window.
- **Kamen's own play** on the new engine, for what only he can judge: sound, feel, and focus after switching away and back. It's short, and on games he's already played (Chants), to keep the others unspoiled.
- **Pass rule:**
  - No check is worse than c2 beyond its normal run-to-run spread (measured, not guessed: run c2 twice).
  - Kamen signs off.
  - Only then does the Steam bottle move to the new engine.

### Phase B: fullscreen
- **The phase A comparison again,** fullscreen engine against phase A's engine. Nothing may get worse.
- **New automatic checks in `cellar check`:**
  - the game's window is in its own macOS Space, in fullscreen (read through Accessibility or the window list, as the 2026-10-31 tests did);
  - its size is the area below the notch;
  - after the game quits, no window of it is left.
- **Kamen's checks:**
  - Mission Control shows the game's tile.
  - Cmd-Tab and swipes work.
  - Desktop 1 is clean.
  - A 16:10 game fills its desktop.
  - Keys work after coming back.

## 7. Left to the builder

- How the fullscreen change behaves inside the Mac driver.
  - Fixed: the behaviour in section 2.
  - Open: which windows qualify (top-level, borderless, covering a screen, the game's main window), when to enter and leave macOS fullscreen, how the game learns its new size below the notch, and how to stop a mode change or a brief resize from sending the window in and out of fullscreen.
- How the build is organised (one script or several, caching, CI layout), and where the bundled libraries come from. Keep the same runtime libraries as today unless one can't be matched.
- The exact `cellar check` measurements for "own Space".
- The order of tasks inside each phase.

## 8. Risks

| Risk | What guards against it |
|---|---|
| Sikarugir's unpublished patches did something games depend on | The phase A comparison on every game. A failing comparison becomes a patch. |
| D3DMetal quietly falls back to Wine's own d3d11 | The engine gate, plus a hard fail in the comparison on "renderer loaded". |
| Steam's login stalls (reported with llvm-mingw) | GCC mingw. The Steam client checks. |
| CrossOver-only behaviour Sikarugir left out, such as its `winetemp` loader hack (breaks when bottles move) or focus differences | The comparison, plus Kamen's focus checks. |
| 25.1.1 doesn't build on macOS 26 | Fallback to CrossOver 26.3, with Kamen told before switching base. |
| The build needs more disk than the free runner has (~14 GB reported) | Build on Kamen's Mac, politely, or trim the build. |
| Rosetta's future (full Rosetta ends after macOS 27) | Unchanged from the Cellar design; out of scope. |

## 9. Done when

- **Phase A:** the Steam bottle runs on Cellar's own source-built engine, every comparison passes, and Kamen has signed off.
- **Phase B:** every game Cellar starts opens in its own desktop like Celeste, nothing is worse than phase A, and Kamen has signed off.
