# M3 checklist: Outer Wilds, Journey, Chants of Sennaar and Leap Year play as on Windows

Kamen's hands-on checks, the same eleven as M2's, once per game. Use the release build: `~/Cellar/.build/release/cellar`
(written as `cellar` below; build it with `swift build -c release` in `~/Cellar`). Steam doesn't need to be open first:
Cellar starts it. Keep Steam for Mac closed while you play (it signs Cellar's Steam out).

Claude already ran each game muted for 2 minutes (`docs/checks/`), so step 2 is optional unless you want your own
report with sound.

## The steps, for each game

1. **One action to play.** `cellar play <id>` reaches the game's menu with no extra steps.
2. **The automatic check** (optional). `cellar check <id>`; play normally until it prints the verdict.
3. **Picture and sound against Windows footage.** Compare the first area with a YouTube playthrough: colours, light,
   nothing missing or flickering; music and effects play, with no crackle or drift.
4. **Cutscene or video.** The game's opening plays, with sound.
5. **Keyboard and mouse.** Everything responds, with no lag you notice.
6. **DualSense.** Optional (deferred since M2).
7. **Saves.** Make the game save, quit from its menu, `cellar play <id>` again: you're where you left off.
8. **Steam Cloud.** After quitting:
   `grep 'AppID <appid>.*Upload complete' ~/Library/Application\ Support/Cellar/bottles/Steam/prefix/drive_c/Program\ Files\ \(x86\)/Steam/logs/cloud_log.txt | tail -1`
   shows `result OK` with today's time.
9. **Quit is clean.** After quitting from the menu, `pgrep -fl '<exe>'` prints nothing.
10. **The regression games.** Once, at the end: `cellar play rain-world` and `cellar play animal-well` reach gameplay.
11. **Your call:** the same as Windows? Anything wrong becomes a profile change or a fix, then that step runs again.

## Per game

| Game | `<id>` | `<appid>` | `<exe>` | Renderer | Notes |
|---|---|---|---|---|---|
| Outer Wilds | `outer-wilds` | 753640 | `OuterWilds.exe` | D3DMetal | First run asks for a profile name. Step 7: play until the first loop ends (22 minutes) or quit after a campfire; the save is kept per loop. Target 60 fps (the game's physics runs at 60 Hz; 120 needs its `PhysicsRate` file and isn't a goal). |
| Journey | `journey` | 638230 | `Journey.exe` | D3DMetal | Step 3: say whether the logos are followed by a black screen; turn on "Cloth Interpolation" in Options if the scarf stutters. Online play (meeting other players) is out of scope. |
| Chants of Sennaar | `chants-of-sennaar` | 1931770 | `Chants Of Sennaar.exe` | D3DMetal | Step 3: text and the glyphs render (fonts are the usual Wine failure). |
| Leap Year | `leap-year` | 2951770 | `Leap Year.exe` | DXVK | D3DMetal stops at an error dialog, so Cellar starts it with DXVK, directly rather than through Steam. No Steam Cloud: step 8 becomes "the save survives quit and relaunch". |

Write down what you saw (or just tell Claude); Claude fills `docs/m3-signoff.md`. M3 is done when every game passes.
