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

## First launch (Claude, muted, with the watchdog), 2026-10-30 20:15-20:34

Kamen OK'd the runs. Steam was restarted muted (`steam-renderer` = `d3dmetal muted`); each game ran through
`cellar play <id> --mute` under a quiet lock, with a process list every 2 s, two silent window captures and `lsof`.
The audio watchdog never fired. Display: 3024 x 1964 (1512 x 982 points).

| Game | Renderer | What happened |
|---|---|---|
| Chants of Sennaar | D3DMetal | Reached the title screen ("Press a button") in under 60 s, full screen (1512 x 982; the picture is 16:9, so black bars top and bottom). D3DMetal's `d3d11.dll`/`dxgi.dll` loaded. No installers. |
| Leap Year | D3DMetal | **Fails.** An error dialog: `Win32 function failed: HRESULT: 0x80070057` (E_INVALIDARG) from `GR_D3D_Device->CheckMultisampleQualityLevels` (GameMaker's `Graphics_DisplayM.cpp`). |
| Leap Year | DXVK | Reached the main menu (Play, Options, Credits, Quit), full screen. DXVK's `d3d11.dll` loaded. It started directly, not through Steam (Steam runs with D3DMetal); Leap Year has no Steam Cloud and doesn't load `steam_api64.dll`, so nothing is lost. |
| Journey | (not reached) | Steam ran Journey's install script first (Visual C++ 2017 x64 and x86, a few seconds), then showed a notice in its window, "Grab a controller and kick back!", with an OK button, and waited (`LaunchApp waiting for user response to ShowInterstitials` in `console_log.txt`). Cellar took the silence for a stuck Steam, restarted it, and Steam showed the notice again. |
| Outer Wilds | (not reached) | The same: Visual C++ 2019 x64 and x86 through `Steamworks Shared/runasadmin.vdf` (about 10 s, with `msiexec`), then the same controller notice. |

Fixed since: while Steam's launch waits on a notice, `cellar play` keeps waiting (as for an installer, up to 10
minutes) and, if nobody answers, says "Steam is waiting for you to answer something in its window before it starts
<game>" instead of restarting Steam.

Still to see: Journey and Outer Wilds past the notice (Kamen presses OK in the Steam window; then another muted look).

## Save folders

Steam Cloud made `AppData/Local/Annapurna Interactive/Journey/Steam` and
`AppData/LocalLow/Mobius Digital/Outer Wilds/SteamSaves` before each launch, which matches both profiles.
`AppData/LocalLow/Rundisc/Chants Of Sennaar` exists, as in its profile. Leap Year wrote no save folder in 90 s at the
menu; its profile keeps `saves: null` until a playthrough shows one.

## Launch options

None needed so far (Task 4 skipped): the one failure, Leap Year on D3DMetal, is solved by DXVK without options.
