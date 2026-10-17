# M0 sign-off

## Automatic (2026-10-17)

- `swift test`: 41/41 pass.
- Real-Wine integration test (`CELLAR_INTEGRATION=1`): pass in 51 s, headless, from a root named `Cellar Tést`, including a real `.exe` under `Games/Animal Well.app/Contents/` run by its Mac path. No Wine app left in the Dock.
- `scripts/m0-acceptance.sh`: **PASS**. In a throwaway root with a clean environment it installed the engine from `https://github.com/kamenlevi/Cellar/releases/tag/engine-sikarugir-10.0_6-c1`, verified SHA-256 `2f2df117…580bde`, created a bottle, and ran `cmd /c echo cellar-ok`. Nothing from Sikarugir, Heroic or Homebrew was used.
- Engine checked against Apple's toolkit files by name and by content (hashes compared with a local D3DMetal 3.0 copy): none inside.

## Kamen's checks

- [ ] `cellar run "M0 Check" notepad` shows a Notepad window at the right Retina size.
- [ ] After downloading the Game Porting Toolkit from Apple himself: `cellar d3dmetal import ~/Downloads/<file>.dmg`, then `cellar d3dmetal status` shows the version.
