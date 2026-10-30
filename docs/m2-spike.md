# M2 spike: how Rain World starts, which renderer, what the logs look like

Run on 2026-10-26 (D3DMetal) and 2026-10-29 (DXVK) with `scripts/m2-spike.sh`, on Kamen's MacBook Pro
(3024x1964, 120 Hz), engine `sikarugir-10.0_6-c1`, D3DMetal 3.0, in the shared `Steam` bottle with Steam signed
in. Kamen chose Rain World (appid 312520, Unity 2020.3.45, D3D11) as the first game instead of Outer Wilds: it is half
the size. Raw outputs are in `.superpowers/spike-<variant>-{hud.log,facts.txt,wine.log}` (not committed).

## 1. Direct launch

`RainWorld.exe` started directly from its Steam folder, with `SteamAppId=312520 SteamGameId=312520` and Steam running
beside it, reaches the menu and plays. No relaunch through Steam, no `-applaunch` needed. The plan's default
(`launch: direct`) holds.

The game window is `Rain World`, 1512x982 at 0,0: the whole logical screen. The Metal HUD shows 3024x1964, "Direct"
(direct to display).

## 2. Renderers

| Variant  | Loaded (lsof)                                                                 | Kamen saw                     | fps at the menu |
|----------|-------------------------------------------------------------------------------|-------------------------------|-----------------|
| d3dmetal | `D3DMetal.framework`, `libd3dshared.dylib`, `d3d11.dll`/`dxgi.dll` from `renderers/d3dmetal/3.0/wine` | menu, clickable, music        | 120, one dip to 40 |
| dxvk     | `libMoltenVK.dylib` (engine Frameworks), DXVK `d3d11.dll` from `renderer/dxvk/wine`, Wine's `dxgi.dll`; writes `RainWorld.dxvk-cache` in the game folder | menu, same picture and music  | 120 median, 6 hitches down to 2 (shaders compiling on a first run) |
| wined3d  | not run                                                                       |                               |                 |

D3DMetal reports itself to Unity as `Direct3D 11.0 [level 11.1]`, renderer `AMD Compatibility Mode`. DXVK is
`DXVK-Kegworks v1.10.4-async`. Both work; D3DMetal stays the default (no shader hitches), DXVK is a real fallback.

**Spike-script bug, fixed:** the first DXVK run crashed (`Failed to load libMoltenVK.dylib`, no Vulkan, Wine's crash
dialog). The script started `wine` through `nohup`, a protected system binary, so macOS removed every `DYLD_*`
variable and Wine found none of the engine's libraries (FreeType and GnuTLS were missing in the D3DMetal run too).
Cellar itself starts `wine` directly, and its logs have no such lines. Rule for later scripts: never put a system
binary (`nohup`, `env`, `/bin/sh -c`, ...) between Cellar and `wine`.

## 3. Metal HUD log

`MTL_HUD_ENABLED=1 MTL_HUD_LOG_ENABLED=1` (the older `MTL_HUD_LOGGING_ENABLED=1` was set too and does no harm).
Captured with:

    log stream --style compact --predicate 'eventMessage CONTAINS "metal-HUD"'

The stream starts with two header lines (`Filtering the log data using ...`, `Timestamp  Ty Process[PID:TID]`).
Each sample then appears **twice**, once tagged `(libMTLHud.dylib)` and once `[com.apple.metal.hud:Logging]`:

    2026-10-26 20:05:47.909 Df wine[74907:26359d2] [com.apple.metal.hud:Logging] metal-HUD: 1707,565.88,1557.19<private>

- The first field is the game's **running frame count**. A sample is written about every 0.41 s.
- The next two fields are two slowly growing numbers (most likely memory in MB); not needed.
- The per-frame intervals that follow are `<private>`: the system log redacts them. There are no frame times to read.

So fps comes from frame-count deltas: (count₂ − count₁) / (time₂ − time₁), e.g. 2638 − 1707 frames in 7.758 s =
120.0 fps. The finest resolution is one 0.41 s sample, so a hitch shows up as one slow sample, not as a frame time.
Real lines are in `Tests/CellarCoreTests/Fixtures/HUDLogFixtures.swift`.

## 4. Audio

While the game plays sound, `pmset -g assertions` shows:

    pid 427(coreaudiod): [0x001734f100019a89] 00:00:43 PreventUserIdleSystemSleep named: "com.apple.audio.80-C3-BA-52-BD-A5:output.context.preventuseridlesleep"
        Resources: audio-out 80-C3-BA-52-BD-A5:output

The assertion belongs to `coreaudiod`, not to the game: it names the output device, never the game's pid, and its
age (`00:00:43`) counts from when sound started on that device. Kamen heard the music in both runs.

## What this changes in the plan (Task 4)

- `FrameStats.parse(hudLog:)` cannot return per-frame intervals (they are private). It returns (time, frame count)
  samples from the `com.apple.metal.hud:Logging` copies only; `averageFPS` and the slowest sample's fps come from
  their deltas. "1% low" becomes "slowest 0.41 s sample".
- `MacFacts.audioPlaying(assertions:pid:)` cannot match the game's pid. It looks for a coreaudiod `audio-out`
  assertion whose age is no older than the game's run time, so music from another app started earlier doesn't count.
  It can't tell the game's sound from another app that started sound after the game did; the playtest covers that.
- Launch mode `direct` and renderer `d3dmetal` are confirmed for Rain World. The Renderer environments in Task 2
  match what worked here.
