# M4 spike: CrossOver 25.1.1 against D3DMetal 3.0

2026-10-31. Source: `crossover-sources-25.1.1.tar.gz` from CodeWeavers, 178,524,083 bytes,
SHA-256 `7cdcfcfaee8991f7958b5ccb2837c0facec6e8e681cd3ada8d2745bddbe27d13`. Downloaded with Kamen's OK.

## The tree

- `sources/wine/VERSION`: **Wine version 10.0**, the same base as engine c2.
- Wine Mono **9.4.0** and Wine Gecko **2.47.4** (`dlls/appwiz.cpl/addons.c`).
- **Already in the tree:**
  - The D3DMetal bridge: `dlls/winemac.drv/d3dmetal.c`, and in `dlls/ntdll/unix/loader.c`, `CX_APPLEGPTK_LIBD3DSHARED_PATH` and the non-native code-region hooks.
  - Wine's focus fix: the made-up `WM_MOUSEACTIVATE(HTMENU)` is gone from `window.c`, so patch 0002 isn't needed.
- **Not in the tree:**
  - `WINEDLLPATH_PREPEND`, so patch 0001 is needed.
  - The fix for the Windows user name: `dlls/advapi32/advapi.c` reports it as "crossover", so patch 0003 is needed.

## Does 25.1.1's bridge match D3DMetal 3.0?

**Yes.** The ruling is to build from CrossOver 25.1.1.

- `libd3dshared.dylib` in Kamen's D3DMetal 3.0 (read in place, not copied):
  - It reads Wine's Mac driver through one exported table, `macdrv_functions`. It also imports `wine_get_dos_file_name` and `wine_get_unix_file_name`.
  - Its exports include `GetMacDRVFunctions` and `register_non_native_code_region`/`supports_non_native_code_regions`. The second pair is what ntdll looks up.
- **The table:** `struct macdrv_functions_t` is the same in 25.1.1 and in CrossOver 26.3, which ships for D3DMetal 3.0: 24 members, in the same order, with the same types, asserted at 192 bytes. Today's engine c2 exports a `macdrv_functions` with the same `my_*` functions behind it.
- **The window data** handed to D3DMetal, `struct d3dmetal_macdrv_win_data`, is asserted at 120 bytes in both trees. The only difference is one extra bit in a bitfield, which doesn't change the layout.
- **What does differ between 25.1.1 and 26.3** is inside the functions, not the interface: 26.3 creates a Wine 11 "client surface" in `get_win_data`.
- **Neither engine's unix libraries export the two file-name helpers,** and D3DMetal 3.0 works on c2 today. So 25.1.1 matches c2 there too.

CrossOver 26.3's file was read from the public mirror `gilnoh/winecx-sources` (tag `winecx-26.3.0`).

## What this changes in the plan

- Patch `0002` is dropped: the focus fix is already in.
- Patches `0001` (`WINEDLLPATH_PREPEND`) and `0003` (the user name) stay.
