# M2 sign-off: Rain World, all the way

Kamen's checklist (`scripts/m2-checklist.md`), on his real Cellar folder, 2026-10-29 and 2026-10-30. M2's game changed from
Outer Wilds to Rain World (Outer Wilds moves to M3); ANIMAL WELL is the regression game.

| # | Check | Result |
|---|---|---|
| 1 | One action to play | ✅ with a gap. On 2026-10-30, Steam had been running since the evening before and silently ignored every launch request (`-applaunch` and `steam://`): nothing in its logs and no game. `cellar steam restart` fixed it, and the game then started in about 1 s. Since the fix, `cellar play` waits up to 45 s for the game. If it doesn't appear, Cellar restarts Steam once (never while another program runs in its bottle) and asks again; if that also fails, it says so. Shown with a fake Steam; real Steam hasn't hit the stale state again since. |
| 2 | The automatic check | ⚠️ No passing report on file. Kamen's 2-minute check (2026-10-29 15:44) failed against the old 120 fps target: it averaged 97 fps with 3 hitches. The target is now the game's 60 fps (57 to pass). Kamen: "It felt smooth to me." |
| 3 | Picture and sound against Windows | ✅ Kamen, 2026-10-30. DXVK looked and sounded the same as D3DMetal too (2026-10-29). |
| 4 | Cutscene | ✅ Kamen, 2026-10-30. |
| 5 | Keyboard | ✅ Kamen, 2026-10-30. |
| 6 | DualSense | ⏸ Not tested. Kamen: "we will deal with later if I need it". |
| 7 | Saves | ✅ The save was written at 16:33:11 and uploaded. The logs show no second launch on 2026-10-30. Restoring a save across launches was shown on 2026-10-29. |
| 8 | Steam Cloud | ✅ `AC Launch` sync at 16:23:39 and `AC Exit` at 16:33:40: `Upload complete, result OK` (commit 51dd0ef). |
| 9 | Quit is clean | ✅ Steam: "Game process removed" at 16:33:40; `pgrep` found nothing. |
| 10 | The regression game | ✅ ANIMAL WELL reached gameplay through Steam with D3DMetal on 2026-10-29 (19:50, Claude's run). It crashes when started with `--mute`: it needs a sound device. |
| 11 | Same as Windows? | ✅ Kamen, 2026-10-30: "everything seemed to work". |

**M2: signed off by Kamen (2026-10-30). The controller is deferred.**
