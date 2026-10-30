# M3 spike: what each game needs on first launch

Kamen installed all four through Cellar's Steam on 2026-10-30 (every `appmanifest_<appid>.acf` at `StateFlags 4`).

## Exe and DirectX (Cellar's `ExeFacts` on the real files)

| Game | Appid | Folder | Exe | 64-bit | DirectX imported |
|---|---|---|---|---|---|
| Outer Wilds | 753640 | `Outer Wilds` | `OuterWilds.exe` | yes | none (Unity: `UnityPlayer.dll` loads it at run time) |
| Journey | 638230 | `Journey` | `Journey.exe` | yes | 11 (also `fmod64.dll`, `libscepad.dll`, `xinput9_1_0.dll`) |
| Chants of Sennaar | 1931770 | `Chants of Sennaar` | `Chants Of Sennaar.exe` | yes | none (Unity) |
| Leap Year | 2951770 | `Leap Year` | `Leap Year.exe` | yes | 11 (also `mf.dll`/`mfplat.dll`: Media Foundation, for video) |

The exe names in `games.json` match. Steam's folder for Chants is `Chants of Sennaar` (lower-case "of"); the exe keeps
"Of". All four are 64-bit, so D3DMetal can run each of them.

## First launch (muted, with the watchdog)

Pending Kamen's OK.
