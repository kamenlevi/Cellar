# M3 sign-off: Outer Wilds, Journey, Chants of Sennaar and Leap Year

Kamen's checklist (`scripts/m3-checklist.md`), on his real Cellar folder, 2026-10-30 and 2026-10-31.

Kamen played Chants of Sennaar. He doesn't want to spoil the other three games by starting them and stopping, so on
2026-10-31 he set the rule for M3: Chants is signed off on his playtest, and Outer Wilds, Journey and Leap Year are
signed off on Claude's muted automatic checks, **provisional until Kamen plays each one**. Anything he finds then
becomes a fix.

## Chants of Sennaar: played

| # | Check | Result |
|---|---|---|
| 1 | One action to play | ✅ `cellar play chants-of-sennaar` reached the game through Steam each time on 2026-10-31. |
| 2 | The automatic check | ✅ 120.0 fps over 2 minutes, muted (2026-10-30 22:18, `docs/checks/chants-of-sennaar-2026-10-30-221840.md`). A 30-second check on 2026-10-31 measured 113 against the 114 target, while the local models were running. |
| 3 | Picture and sound against Windows | ✅ Kamen: "everything is really really well", "from what i saw it was good enough". Text and glyphs render. |
| 4 | Cutscene | ✅ Kamen played about 40 minutes on 2026-10-31 (00:39–01:19) and more later that morning. |
| 5 | Keyboard and mouse | ✅ after a fix. The keys died after a focus change (Cmd-Tab, or Spotify bringing itself forward): a Wine Mac-driver focus bug. Engine c2 fixes it (`docs/engines.md`). Kamen, 2026-10-31: "whatever i did i wasnt able to break it". Steam's in-game overlay is now kept out of games too (2aff510), found while chasing the same bug. |
| 6 | DualSense | ⏸ Deferred, as in M2. |
| 7 | Saves | ✅ Progress kept across Kamen's sessions on 2026-10-31. |
| 8 | Steam Cloud | ✅ `AC Exit` sync at 13:07:02 on 2026-10-31: `Upload complete`. |
| 9 | Quit is clean | ✅ Steam logged "Game process removed" at 13:07:02; nothing left running. |
| 11 | Same as Windows? | ✅ Kamen: "chants of senaar play pretty good id say". |

Kamen also saw a short stutter about every 5 minutes. It matched the local-model jobs' 5-minute load cycle exactly (`~/Library/Logs/health.csv`, 2026-10-31 00:39–01:19), not anything in the game or Cellar.

## Outer Wilds, Journey, Leap Year: automatic checks, provisional

Claude's muted checks, 2026-10-30 (`docs/checks/`). Each game reached its menu through `cellar play`; nothing past the
title screens was tried, to keep the games unspoiled.

| Game | Renderer | Automatic check | Open for Kamen's playthrough |
|---|---|---|---|
| Outer Wilds | D3DMetal | ✅ PASS: 104.5 fps (target 57; the game runs at 60). | The first loop, a save after a campfire, Steam Cloud. |
| Journey | D3DMetal | ⚠️ 86.7 fps at the menu against the 120 Hz target of 114, slowest 70, no hitches. | Whether it feels smooth; whether the logos are followed by a black screen; the scarf. |
| Leap Year | DXVK | ✅ 60.0 fps steady (the game's own 60; target 57). A re-check recorded frames for only 22 s and didn't see the window at the end, the same flake seen once with Chants and Rain World. | Saves (no Steam Cloud for this game). D3DMetal stops at an error dialog, so Cellar starts it directly with DXVK. |

## Regression games

| Game | Result |
|---|---|
| Rain World | ✅ PASS: 118.8 fps over 40 s, muted (2026-10-30 22:09). |
| ANIMAL WELL | ⏸ Not re-run in M3: it crashes without a sound device, so only Kamen runs it. It last reached gameplay on 2026-10-29 (M2). |

## Found in M3, for later

- **Real macOS fullscreen.** Games open as a borderless window the size of the screen on the normal desktop, not in their
  own Space, so other windows show black around them. Chants ignores every "start windowed" switch, and the engine's Mac
  driver has no public source, so this needs Cellar's own engine built from source (as `diacunap/wine-cx-sikarugir` does
  from CrossOver's). A milestone of its own.
- **Spotify brings itself forward** now and then while a game is in front. With engine c2 the game keeps its keys when it
  gets focus back, but the game is still interrupted.

**M3: signed off by Kamen (2026-10-31) for Chants of Sennaar; Outer Wilds, Journey and Leap Year provisional until he
plays them. The controller is deferred.**
