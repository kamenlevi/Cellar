# Cellar engines

Cellar runs games on engines it hosts itself, as assets on this repo's GitHub releases, so no outside server going away can break it (that is what killed Whisky). The app downloads engines only from here; `Sources/CellarCore/Resources/engines.json` pins each one by URL, SHA-256 and size.

## sikarugir-10.0_6-c2 (default)

The c1 engine below with one fix in Wine's Mac driver, and nothing else changed. A bottle made with c1 moves to c2 the next time Cellar starts its Steam fresh (`replaces` in `engines.json`); nothing in the prefix changes.

- **The focus fix.** Without it a Unity game that loses focus and gets it back (Cmd-Tab, a click on another app, an app that brings itself forward, such as Spotify) keeps drawing but drops every key and click. Found with Chants of Sennaar on 2026-10-31; with the fix, Kamen couldn't break it.
- **What changes.** Sikarugir's revision 6 has no public source, so `scripts/package-engine.sh` makes three byte edits to its `winemac.so`, each checked against the bytes it replaces, and re-signs it ad hoc. Any other `winemac.so` stops the build, and `--check` refuses an engine whose `winemac.so` isn't the fixed one (SHA-256 `87cda88a…`).
  1. `macdrv_window_got_focus`: no made-up `WM_MOUSEACTIVATE(HTMENU)` before activating the window; straight to "setting foreground window". This is upstream Wine commit b568eaac4a (wine-10.6, Wine bug 48121).
  2. `makeFocused`: discard only `WINDOW_LOST_FOCUS`, not `WINDOW_GOT_FOCUS` (CrossOver hack 18896).
  3. `windowDidBecomeKey`: no early return when Wine itself made the window key (CrossOver hack 18896).
- **Credit.** [Highball](https://github.com/gauthierpiarrette/highball) found and described this fix. Cellar's offsets come from its own disassembly of the same file; none of Highball's code is used.

## sikarugir-10.0_6-c1

- **Wine:** 10.0, Sikarugir revision 6 (`WS12WineSikarugir10.0_6.tar.xz`, release `v1.0` of [Sikarugir-App/Engines](https://github.com/Sikarugir-App/Engines)). This engine is the one that ran the Windows Steam client and ANIMAL WELL on Kamen's Mac in August 2026.
- **Runtime libraries:** `Contents/Frameworks` of `Template-1.0.11.tar.xz`, release `v1.0` of [Sikarugir-App/Wrapper](https://github.com/Sikarugir-App/Wrapper): GnuTLS, FreeType, SDL2, MoltenVK, GStreamer and their dependencies. DXVK, D9VK (DXVK's D3D9) and DXMT come from its `renderer/` folder.
- **Left out:** Apple's D3DMetal (`renderer/d3dmetal`, `apple_gptk`). Its licence does not allow redistribution, so Cellar imports it from Kamen's own Game Porting Toolkit download (`cellar d3dmetal import`). Also left out: `cnc-ddraw` and `SikarugirSdk.framework`, which Cellar does not use.

Layout inside the tarball:

```
sikarugir-10.0_6-c1/
  ENGINE.json        id, Wine version, source assets, build time
  wine/              bin/wine, bin/wineserver, lib/, share/
  Frameworks/        runtime libraries (found through DYLD_FALLBACK_LIBRARY_PATH)
  renderer/          dxvk, d9vk, dxmt
```

## Rebuilding

```bash
scripts/package-engine.sh "$TMPDIR/cellar-pkg"
```

It downloads the two Sikarugir assets, assembles the folder above, and runs `--check`, which fails if any `@rpath` library is missing or if D3DMetal ended up inside. It then prints the tarball's SHA-256 and size for `engines.json`.

## Licences and source

Wine is LGPL-2.1. Its source, including Sikarugir's patches, is at [Sikarugir-App](https://github.com/Sikarugir-App) and [winehq.org](https://www.winehq.org). DXVK is zlib-licensed, MoltenVK Apache-2.0, GStreamer LGPL, and SDL2 zlib. Each library keeps its own licence; Cellar's own code is MIT.
