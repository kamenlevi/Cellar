# M1 sign-off: Steam that works

Kamen's checklist (`scripts/m1-checklist.md`), run on his real Cellar folder, 2026-10-17 to 2026-10-26.

| # | Check | Result |
|---|---|---|
| 1 | Install, first start, sign in | ✅ 2026-10-17. Steam self-updated, then Kamen signed in himself. |
| 2 | `cellar steam status` healthy | ✅ after fix a91b157. Windows line endings (`\r\n`) had hidden both Steam's logs and the process list from Cellar. |
| 3 | Download a game | ✅ ANIMAL WELL installed in the Steam bottle (`StateFlags 4`, 35 MB). |
| 4 | Quit from Steam's menu, come back signed in | ✅ signed in again with no password (2026-10-18 14:24). |
| 5 | Recover from a forced stop | ✅ after fix c729885. Steam's first start after a forced stop loses its window process (`steamwebhelper.exe`) once. `cellar steam` now notices and restarts it once by itself. Re-run 2026-10-26: "Steam came up without its window, so Cellar restarted it once.", then signed in at 19:03 with the window on screen. |
| 6 | `cellar steam` while open | ✅ "bringing its window forward". One Steam window. |
| 7 | One week later | ✅ 2026-10-26, 8 days later: signed in by itself at 19:01, no crash loop. "Last update check" stayed at 18 October because Steam was closed all week. Steam's self-update was proven on day one. |
| 8 | Account id kept out of Cellar's log | ✅ `grep -c '\[U:1:[0-9]' Steam.log` = 0, and no 64-bit Steam ids either. |

**M1: done (2026-10-26).**
