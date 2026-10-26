#!/bin/bash
# M2 spike (throwaway, kept as a record): start a game (Rain World by default) directly in the shared Steam bottle with one
# renderer, capture the Metal HUD log for 60 s, and note which renderer libraries loaded and whether audio plays.
#
#   scripts/m2-spike.sh d3dmetal|dxvk|wined3d [rain-world|outer-wilds]   (default: rain-world)
#
# Run by Kamen only (it opens the game). Steam must be running first: cellar steam
set -euo pipefail
variant="${1:?usage: m2-spike.sh d3dmetal|dxvk|wined3d [rain-world|outer-wilds]}"
case "${2:-rain-world}" in
  rain-world)  appid=312520; exe_name="RainWorld.exe"; title="Rain World" ;;
  outer-wilds) appid=753640; exe_name="OuterWilds.exe"; title="Outer Wilds" ;;
  *) echo "unknown game ${2}"; exit 1 ;;
esac

root="$HOME/Library/Application Support/Cellar"
engine="$root/engines/sikarugir-10.0_6-c1"
prefix="$root/bottles/Steam/prefix"
steamapps="$prefix/drive_c/Program Files (x86)/Steam/steamapps"
d3dmetal="$root/renderers/d3dmetal/3.0"
out="$(cd "$(dirname "$0")/.." && pwd)/.superpowers"
mkdir -p "$out"

manifest="$steamapps/appmanifest_$appid.acf"
[ -f "$manifest" ] || { echo "$title isn't installed in Cellar's Steam yet."; exit 1; }
grep -q '"StateFlags"[[:space:]]*"4"' "$manifest" || { echo "$title is still downloading."; exit 1; }
installdir=$(sed -n 's/.*"installdir"[[:space:]]*"\(.*\)".*/\1/p' "$manifest")
game="$steamapps/common/$installdir"
"$HOME/Cellar/.build/release/cellar" steam status | grep -q "Running: yes" || { echo "Start Steam first: cellar steam"; exit 1; }

# Same environment as Cellar's interactive mode (WineEnvironment.make), minus anything from this shell.
for v in $(env | grep -oE '^(WINE[A-Z_]*|DYLD_[A-Z_]*)=' | tr -d =); do unset "$v"; done
export WINEPREFIX="$prefix"
export MVK_CONFIG_LOG_LEVEL=1
export DYLD_FALLBACK_LIBRARY_PATH="$engine/Frameworks:$engine/Frameworks/GStreamer.framework/Versions/1.0/lib:$engine/wine/lib/wine/x86_64-unix:/usr/lib"
export PATH="$engine/wine/bin:$PATH"
overrides="mscoree,mshtml=;winemenubuilder.exe=d"

# Spike additions.
export SteamAppId=$appid SteamGameId=$appid
export WINEDEBUG="fixme-all,err+all"
export MTL_HUD_ENABLED=1 MTL_HUD_LOG_ENABLED=1 MTL_HUD_LOGGING_ENABLED=1
export ROSETTA_ADVERTISE_AVX=1

case "$variant" in
  d3dmetal)
    export WINEDLLPATH_PREPEND="$d3dmetal/wine"
    export DYLD_FALLBACK_LIBRARY_PATH="$d3dmetal/external:$DYLD_FALLBACK_LIBRARY_PATH"
    export DYLD_FALLBACK_FRAMEWORK_PATH="$d3dmetal/external"
    overrides="$overrides;d3d11,d3d12,d3d10core,dxgi=b" ;;
  dxvk)
    export WINEDLLPATH_PREPEND="$engine/renderer/dxvk/wine"
    overrides="$overrides;d3d11,d3d10core,dxgi=n,b" ;;
  wined3d) ;;
  *) echo "unknown variant $variant"; exit 1 ;;
esac
export WINEDLLOVERRIDES="$overrides"

hud="$out/spike-$variant-hud.log"
facts="$out/spike-$variant-facts.txt"
gamelog="$out/spike-$variant-wine.log"
log stream --style compact --predicate 'eventMessage CONTAINS "metal-HUD"' > "$hud" 2>&1 &
logpid=$!

echo "Starting ${title} with ${variant}…"
(cd "$game" && nohup wine "$game/$exe_name" > "$gamelog" 2>&1 &)

sleep 45
gpid=$(pgrep -f "$exe_name" | head -1 || true)
{
  echo "variant: $variant   game pid: ${gpid:-not found}   time: $(date '+%H:%M:%S')"
  echo "--- libraries"
  [ -n "${gpid:-}" ] && lsof -p "$gpid" 2>/dev/null | grep -iE 'D3DMetal|d3dshared|dxvk|MoltenVK|d3d1[012]|dxgi' | awk '{print $NF}' | sort -u
  echo "--- audio assertions"
  pmset -g assertions | grep -iE 'audio|coreaudio' || true
  echo "--- windows"
  printf '%s\n' 'import CoreGraphics' 'for w in (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []) where (w[kCGWindowOwnerName as String] as? String) == "wine" { print(w[kCGWindowName as String] ?? "-", w[kCGWindowBounds as String] ?? "") }' > "$out/windows.swift"
  swift "$out/windows.swift" 2>/dev/null || true
} > "$facts"

sleep 15
kill "$logpid" 2>/dev/null || true
echo "Captured: $(grep -c metal-HUD "$hud" || true) HUD lines. Notes in $facts"
echo "Now tell Claude: menu reached? picture right? sound? Then quit the game from its menu."
