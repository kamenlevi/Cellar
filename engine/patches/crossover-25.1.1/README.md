# Cellar's patches to CrossOver 25.1.1

Applied in order by `scripts/build-engine.sh` to `sources/wine` of `crossover-sources-25.1.1.tar.gz`
(CodeWeavers, 178,524,083 bytes). Each is LGPL-2.1, like Wine.

| Patch | What it does | From |
|---|---|---|
| `0001-ntdll-winedllpath-prepend.patch` | Looks in `WINEDLLPATH_PREPEND` before Wine's own DLLs, which is how Cellar loads the user's imported D3DMetal | MacPorts `game-porting-toolkit/files/1005-ntdll-d3dmetal-env.diff` |
| `0002-real-windows-user-name.patch` | Reports the real Windows user name and its profile folder, not CrossOver's "crossover", so existing bottles keep their saves | Upstream wine-10.0's `advapi.c` and `shellpath.c` |

Wine's focus fix (b568eaac4a) is already in CrossOver 25.1.1 (`docs/m4-spike.md`).
