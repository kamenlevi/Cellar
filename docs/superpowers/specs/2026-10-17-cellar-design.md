# Cellar — design

Date: 2026-10-17 · Author: Kamen (with Claude) · Status: draft for Kamen's approval

## 1. What this is, and why

Kamen buys indie games on Steam because they look wonderful and have overwhelming reviews, then finds out they are Windows-only and never plays them. About 20 of the games he owns are in that state. His Mac is an M5 Pro (Apple Silicon) on macOS 26.5.

Cellar is his own macOS app for playing those games. It is a native shell around the same compatibility stack every other Mac app of this kind uses — **Wine** (runs Windows programs), **Apple's D3DMetal** from the Game Porting Toolkit and **DXVK + MoltenVK** (translate DirectX to Metal), and **Rosetta 2** (translates x86 to Apple Silicon). Nobody writes a new Wine; that was ruled out in August as a decades-long job.

Why build it instead of using Heroic, CrossOver or Sikarugir:

- **Ownership.** Kamen does not want to depend on someone else's interface or someone else's update schedule. In his words, "so it is mine and I am not dependent on anything."
- **Permanence.** The Animal Well setup (a hand-tuned Sikarugir wrapper) worked, but every fix was manual: D3DMetal switched on by hand, RetinaMode added to the registry by hand, a helper script to launch the game. He wants a permanent answer, where buying a game means being able to play it.
- **Hosting.** Whisky died in practice when its runtime host (`data.getwhisky.app`) started returning 404. Cellar keeps its own copies of everything it is allowed to redistribute.

It is a personal project, open source on GitHub (`kamenlevi/Cellar`), "nothing serious" — but it should work properly for him.

## 2. Goals, non-goals, anti-goals

**Goals**

1. Kamen's target games run **the same as they would on a Windows PC**: visuals, audio and music, controller, saves, gameplay, smoothness. Frame rate cannot literally match a Windows PC (translation costs something), so the practical bar is that each game holds its frame-rate cap with no stutter.
2. Each game starts with **one action and no manual fixes**. What a game needs (which DirectX translation, Retina mode, and so on) is worked out by Cellar, not tweaked by hand.
3. Cellar keeps working when outside things change. Engines are pinned and mirrored, and Steam updates do not break it silently.
4. Eventually, a native Mac app whose library shows every game Kamen owns on Steam, downloaded or not, with a clear "will it run" status on each.

**Non-goals**

- Writing our own Win32 or DirectX implementation.
- Online games with kernel or EA anti-cheat (skate., Where Winds Meet). These are blocked for every Wine-based app.
- Big AAA performance work.
- Non-Steam stores (Kamen buys only on Steam).
- Windows desktop tools from his library (Wallpaper Engine, Lossless Scaling).
- Getting around DRM or emulating Steam's API. Games that need Steam get the real Steam client.

**Anti-goals** (these would make Cellar a failure even if it technically works)

- Hand-tuning each game, the way Animal Well was done.
- Depending on a download server that can vanish, Whisky-style.
- Building the interface before the engine is good. Kamen was explicit: **engine first, UI last.**

## 3. Target games

Chosen by Kamen. Data from Steam, PCGamingWiki and ProtonDB, gathered 2026-10-17. ProtonDB rates Linux Proton, the closest public evidence for Wine on a Mac.

| Game | Steam appid | Engine | Graphics | ProtonDB | Notes |
|---|---|---|---|---|---|
| Outer Wilds | 753640 | Unity | D3D11 | platinum (400) | One of his two favourites |
| Journey | 638230 | PhyreEngine | D3D11 | platinum (116) | Failed in August only because Steam would not start (old Wine 7.7 vs the 2026 Steam client) |
| Rain World | 312520 | Unity | D3D11 | platinum (158) | The current version has no Mac build |
| Chants of Sennaar | 1931770 | Unity | D3D11 (presumed) | platinum (52) | |
| Leap Year | 2951770 | unknown | D3D10 | gold (14) | Chosen over PEAK by Kamen; the only D3D10 target |

Already known to work by hand: **ANIMAL WELL** (813230, custom engine, D3D12 only → needs D3DMetal). Use it as a regression check.

Kamen's other Windows-only games, for later: PEAK (online co-op, needs a second player to test), Ori and the Will of the Wisps, Perspective, DYO, Librarian, Steam Engine Simulator, Unravel Two, Grimm's Hollow, Sheepy, MECCHA CHAMELEON (UE5, D3D12), Anno 1800 (needs Ubisoft Connect), It Takes Two (needs the EA app). Three Mac-listed games show as blocked in Mac Steam: Janosik, Missing Translation and Sigils of Elohim. They are probably 32-bit Mac builds (a guess, not yet checked), and their Windows builds could run through Cellar.

## 4. The bar, and how we check it without a Windows PC

Kamen has no Windows PC to compare against. "Same as Windows" is judged from four sources:

1. **Reference footage.** Gameplay video (YouTube) of the same scenes, to compare look and sound.
2. **Known-issue lists.** PCGamingWiki and ProtonDB entries for each game: what breaks under Wine and which setting fixes it.
3. **Automatic checks Cellar runs itself:**
   - frame pacing and FPS via Apple's Metal performance HUD or an equivalent;
   - Wine log scan for errors and missing DLLs;
   - audio actually playing (a non-silent output device stream);
   - controller detected and mapped;
   - window fills the display at native scale;
   - the game survives a quit and relaunch, with saves intact.
4. **Kamen plays it.** A game counts as done only when he has played it and agrees.

A per-game checklist, used at every milestone: launches with one action · reaches gameplay · visuals match reference · music and sound effects play with no crackle · cutscenes and video play · keyboard and mouse work (Kamen's usual input) · a PlayStation DualSense works, rumble included where the game has it (he uses one rarely, so this check is lower priority but still required) · holds its frame cap (60 Hz, or 120 Hz where the game supports it) without stutter · saves persist and Steam Cloud sync works · quit and relaunch is clean.

## 5. Constraints

- Apple Silicon M5 Pro, macOS 26.5. Wine and D3DMetal run as x86_64 under Rosetta 2; that is expected.
- Every game comes from Steam. Most of the targets expect the Steam client to be running (Steamworks), so **Cellar must run the real Windows Steam client reliably**. This was the part that failed in August: Heroic paired Steam with GPTk's Wine 7.7, and the 2026 Steam client's embedded Chromium (`steamwebhelper`) crash-looped 216 times. A Wine 10 build (Sikarugir's `WS12WineSikarugir10.0_6`) ran the same Steam client fine on 2026-08-12.
- **Licensing.**
  - Wine is LGPL, so our builds can be published in the repo's GitHub releases. Those releases are our mirror.
  - Apple's D3DMetal / Game Porting Toolkit licence does not allow re-uploading it. Kamen signs in to Apple once and downloads the Game Porting Toolkit himself (he agreed to this); Cellar finds it and takes D3DMetal from there, or from a copy already on his Mac, and must cope cleanly if Apple changes the package.
  - DXVK and MoltenVK are open source and can be mirrored.
- **Kamen does every login himself.** That includes Steam username, password and Steam Guard. Cellar and its builders never handle credentials.
- **Kamen's Mac is shared with his own work.** Kamen's native Mac Steam app uses ports 27060/27036. Cellar's Windows Steam must coexist with it or ask him to quit it.

## 6. How it is built — decided

- **A native shell over the existing stack** (section 1). The value Cellar adds is everything between "a Windows game" and "it runs well".
- **Cellar owns its engines.** It picks specific Wine builds and pins them. Each engine Cellar uses is published as a release asset on `kamenlevi/Cellar`, so the app never depends on a third-party host. Upgrading an engine is a deliberate step, never automatic.
- **Per-game settings are worked out, not hand-tuned.** For example, the graphics path comes from the game's executable imports: `d3d12` → D3DMetal; `d3d11`/`d3d10` → D3DMetal or DXVK, whichever passes the checks; `d3d9` and older → DXVK/wined3d. Retina mode is on by default. Per-game exceptions live in a data file in the repo, not in code.
- **Engine first, UI last.** Until the final milestones, Cellar is driven from a command line (`cellar …`) and test scripts.
- **The UI**, when it comes, is a native Swift/SwiftUI Mac app. Its library has **three switchable views**, all wanted by Kamen:
  - **Wall of covers:** tall posters, with filters for All / Downloaded / Windows only / Has a Mac version.
  - **Big game up top:** the current game large with a Play button, rows of games below.
  - **Mac-style list:** a sidebar of groups (Downloaded, Not downloaded, Ready, Needs work, Won't run, Favourites) and a sortable table.

  Every view shows owned-but-not-downloaded games dimmed, and a status tag: Ready / Should run / Needs work / Won't run / Mac version. Mockups are in `docs/mockups/library-home.html`.

## 7. Milestones

Each one ends with something Kamen can try, and none starts until he has signed off the previous one.

**M0 — Groundwork.**
- Repo, licence, a `cellar` command-line tool.
- Cellar can create a bottle (Wine prefix) from a pinned engine it downloaded from its own GitHub release, and run a Windows program in it.
- **Done when:** a fresh Mac user account could run `cellar` and get a working bottle without touching Sikarugir, Heroic or Homebrew taps. The only manual step allowed is Kamen's one-time Game Porting Toolkit download from Apple, and `cellar` tells him exactly when and where to do it.

**M1 — Steam that works.**
- Windows Steam installs into a Cellar bottle, boots to the sign-in screen, and stays stable after Kamen signs in.
- Downloading a game works, and so does surviving a Steam self-update.
- The known failure modes are handled: stale game state after an unclean exit, the CEF sandbox (`-no-cef-sandbox`), port clashes with Mac Steam.
- **Done when:** Kamen can sign in once and Steam is still working a week later.

**M2 — First game, all the way.**
- Outer Wilds launches with one `cellar` command straight into the game, and passes the full section 4 checklist.
- The automatic checks from section 4 exist as a harness, not as manual steps.
- **Done when:** Kamen plays Outer Wilds and calls it the same as Windows.

**M3 — All target games.**
- Journey, Rain World, Chants of Sennaar and Leap Year each pass the checklist.
- Whatever each one needed becomes either an automatic rule or a data-file entry.
- ANIMAL WELL keeps passing.
- **Done when:** every target game has been played and signed off by Kamen.

**M4 — Cellar's own engine, and real macOS fullscreen.** (Added 2026-10-31; design in `docs/superpowers/specs/2026-10-31-m4-own-engine-native-fullscreen-design.md`.)
- Phase A: Cellar builds its own Wine engine from CodeWeavers' public CrossOver source, matching the engine before it on every game.
- Phase B: every game opens straight into its own macOS desktop (Space), like a native Mac game.
- **Done when:** both phases are signed off by Kamen, with nothing worse than before.

**M5 — Automatic for new games.**
- Given any Steam appid Kamen owns, Cellar picks the settings itself (graphics path from the executable, known fixes from PCGamingWiki/ProtonDB data where useful) and predicts a status: Ready / Should run / Needs work / Won't run.
- **Done when:** three games from his "for later" list that Cellar has never seen work on the first try, or are correctly marked "Needs work" / "Won't run".

**M6 — Built to last.**
- Engine upgrades on Kamen's terms: try the new engine on a copy of a bottle, run the checks, then switch.
- Saves are backed up outside the bottle.
- Recovery from crashes and stuck state.
- **Done when:** a Steam update and an engine upgrade both go through without breaking any target game.

**M7 — The app.**
- The SwiftUI app with the three library views over everything above.
- Kamen's own UI ideas (not yet collected — see section 9) are designed in this milestone.
- **Done when:** Kamen uses the app instead of the command line.

**Later, not committed:**
- Mac-native games in the same library.
- Rescuing the 32-bit Mac games via their Windows builds.
- More of the "for later" list.

## 8. Lessons already learned (from the Animal Well and Journey work)

- A fresh Sikarugir wrapper has every renderer switched off. A D3D12-only game then falls back to Wine's own d3d12, which does nothing useful on macOS: music plays, the screen stays black. **Check the executable's imports first.**
- With no `RetinaMode` the game draws 1:1 into backing pixels and fills ⅔ of the Retina screen. Set `"RetinaMode"="y"` under `[Software\\Wine\\Mac Driver]`.
- Running `wine reg add` outside the launcher's environment with D3DMetal on exits with SIGFPE and kills the wineserver, taking any running game with it. Edit `user.reg` with the session stopped instead.
- **Stale Steam state.** After an unclean exit, Steam keeps the old game "running" and `-applaunch` silently does nothing. The fix is to kill the wineserver, wait, then relaunch.
- **Dock icons.**
  - Every Foreground Wine process gets its own Dock icon. With Steam there are two: a phantom `Steam.exe` with no windows, and the real UI.
  - Kamen rejected `-silent`, because it hid Steam with no way to reach it after the game quit. **Steam must stay reachable.**
  - Window geometry can be read without Screen Recording permission via `CGWindowListCopyWindowInfo`.
- **Library paths.** Engine dylibs live in the wrapper's `Contents/Frameworks`. Running `wine` directly needs `DYLD_FALLBACK_LIBRARY_PATH` pointed there.
- **Engine sources.** Sikarugir's `Engines` repo is a good reference and a starting point (40 builds, including GPTk, CrossOver-based and WhiskyWine runtimes). Gcenx's Wine builds are what Heroic uses.

## 9. Calls made by Claude (Kamen to check)

- **Where the list of owned games comes from:** the signed-in Windows Steam client's local data inside Cellar's bottle. No Steam Web API key, and no stored credentials. If that turns out incomplete in M4, revisit it then.
- **Automatic checks and Kamen's working Mac.** Kamen's standing rule: test windows must never come on top of his windows or take focus. So:
  - anything that runs unattended stays invisible and silent;
  - checks that need a visible, audible game (frame pacing, audio, the full checklist) run only when Kamen starts them.
  - This means D3DMetal-vs-DXVK selection in M4 uses unattended evidence (imports, logs, quick headless runs). Full playthrough checks are on request.
- **Steam before the app exists (M1–M5):** the Windows Steam window is Kamen's store and download manager, and `cellar` launches games. "Reachable" means Steam has a visible window and can always be brought back with `cellar steam`. The phantom second Dock icon is acceptable, as it was for Animal Well.
- **Rosetta's future.** Apple has said full Rosetta 2 ends after macOS 27, with a subset kept for older games. Cellar pins x86_64 engines and accepts this risk for now. Re-check when the first macOS 28 beta appears. An ARM64 Wine path is out of scope until then.

## 10. Left open

**Left to the builder:**
- whether M0 starts from an existing engine build (Sikarugir/Gcenx) mirrored into our releases, or builds Wine from source — either meets the "we own our copy" goal;
- the bottle layout (one shared Steam bottle for all games, or one per game);
- the language for the command-line tool (Swift is the natural choice, since the app will be SwiftUI);
- the check harness's exact tools.

**Still to collect from Kamen, before M6:**
- His UI ideas. He has "many"; none are written down yet.
