# M0 sign-off

## Automatic (2026-10-17)

- `swift test`: 41/41 pass.
- Real-Wine integration test (`CELLAR_INTEGRATION=1`): pass in 51 s, headless, from a root named `Cellar Tést`, including a real `.exe` under `Games/Animal Well.app/Contents/` run by its Mac path. No Wine app left in the Dock.
- `scripts/m0-acceptance.sh`: **PASS**. In a throwaway root with a clean environment it installed the engine from `https://github.com/kamenlevi/Cellar/releases/tag/engine-sikarugir-10.0_6-c1`, verified SHA-256 `2f2df117…580bde`, created a bottle, and ran `cmd /c echo cellar-ok`. Nothing from Sikarugir, Heroic or Homebrew was used.
- Engine checked against Apple's toolkit files by name and by content (hashes compared with a local D3DMetal 3.0 copy): none inside.

## Kamen's checks

- [x] **Notepad at the right Retina size.** Passed on the third try.
  - First try: everything came out half size. The bottle had Retina mode on but Windows' default 96 DPI. Fixed in 6b4c56e: bottles now get 192 DPI (200%), like Windows on a Retina-class display.
  - Second try: the menus were right, but the text area was still tiny. Wine's Notepad defaults to "System" 9 pt, a bitmap font that can't scale.
  - Third try: with Notepad set to Tahoma 11 pt in the test bottle, the text was a normal size. That font change is a Notepad setting only and is not in Cellar's defaults, since games draw their own text.
- [x] **D3DMetal imported from Kamen's own download.** He downloaded `Evaluation_environment_for_Windows_games_3.0.dmg` from Apple and ran `cellar d3dmetal import` himself. `cellar d3dmetal status` shows `D3DMetal 3.0`.

**M0: done (2026-10-17).**
