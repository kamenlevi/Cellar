# Cellar

Kamen's own macOS app for playing Windows-only Steam games on Apple Silicon. It is a native shell over Wine, Apple's D3DMetal and DXVK; Cellar keeps its own copies of the engines it runs, so nothing outside the repo can break it. See `docs/superpowers/specs/2026-10-17-cellar-design.md`.

**M0:** command line only (`cellar`).

## Using it (M0)

```bash
cellar doctor                       # what this Mac still needs, with exact fixes
cellar engine install               # Cellar's pinned Wine engine, from this repo's releases
cellar bottle create "Outer Wilds"  # a Windows setup (Retina mode on by default)
cellar run "Outer Wilds" notepad    # run a Windows program; a .exe path works too
cellar bottle kill "Outer Wilds"    # stop everything in that bottle, and nothing else
cellar d3dmetal import ~/Downloads/<Game Porting Toolkit>.dmg   # Apple's D3DMetal, from your own download
```

Tests: `swift test`. The real-Wine test runs with `CELLAR_INTEGRATION=1 swift test` (headless; set `CELLAR_ENGINE_TARBALL` to use a local engine tarball). The whole M0 check is `scripts/m0-acceptance.sh`.
