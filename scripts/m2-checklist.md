# M2 checklist: Rain World plays as on Windows

Kamen's hands-on checks. Use the release build: `~/Cellar/.build/release/cellar` (written as `cellar` below; build it
with `swift build -c release` in `~/Cellar`). Steam doesn't need to be open first: Cellar starts it.

1. **One action to play.** Run `cellar play rain-world`. Rain World reaches its menu with no extra steps. Quit it from
   its menu (Exit).
2. **The automatic check.** Run `cellar check rain-world`. It starts the game and measures for 2 minutes: get into a
   level and play normally until it prints the verdict. Expect `PASS (automatic part)`. The report's path is printed
   (in `~/Library/Logs/Cellar/checks/`); Claude copies the one you sign off into `docs/checks/`. Keep playing for the
   next steps.
3. **Picture and sound against Windows footage.** Play through the first area (the Outskirts) and compare with a
   YouTube playthrough of the same place: the colours, the light and shadow, the rain when it comes, nothing missing or
   flickering. Music and sound effects play, with no crackle or drift.
4. **Cutscene.** The intro slideshow, with its music, plays when a new game starts in an empty save slot. Optional,
   if you have a spare slot.
5. **Keyboard.** Moving, jumping, grabbing, throwing and the map all respond, with no lag you notice.
6. **DualSense.** Connect it, then play a bit: menus, movement, throwing. It rumbles when you get hit (Vibration is on
   in Rain World's options). This check matters less, but it's still required.
7. **Saves.** Play until you hibernate in a shelter (that ends a cycle and saves). Quit from the game's menu. Run
   `cellar play rain-world` again: your cycle and karma are where you left them.
8. **Steam Cloud.** After quitting, run:
   `grep 'AppID 312520.*Upload complete' ~/Library/Application\ Support/Cellar/bottles/Steam/prefix/drive_c/Program\ Files\ \(x86\)/Steam/logs/cloud_log.txt | tail -1`.
   It shows `result OK` with today's time.
9. **Quit is clean.** After quitting from the game's menu, `pgrep -fl RainWorld` prints nothing.
10. **The regression game.** `cellar play animal-well` reaches gameplay.
11. **Your call:** the same as Windows? If yes, M2 is done. Anything wrong becomes a profile change or a fix, and then
    that step runs again.

Write down what you saw in `docs/m2-signoff.md` (or just tell Claude). M2 is done when all of these pass.
