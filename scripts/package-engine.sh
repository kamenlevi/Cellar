#!/bin/bash
# Builds Cellar's engine tarball from Sikarugir's public engine and wrapper template, with the focus fix
# below applied to Wine's Mac driver.
#
#   scripts/package-engine.sh <workdir>          download, assemble, tar, print sha256 and size
#   scripts/package-engine.sh --check <folder>   verify every @rpath dependency resolves
#
# D3DMetal is Apple's and may not be redistributed: it is left out, and the build fails if
# anything named d3dmetal or apple_gptk ends up in the output.
set -euo pipefail

ENGINE_ID="sikarugir-10.0_6-c2"
WINE_VERSION="10.0 (Sikarugir revision 6)"
ENGINE_ASSET="WS12WineSikarugir10.0_6.tar.xz"
TEMPLATE_ASSET="Template-1.0.11.tar.xz"

# The focus fix. Without it a Unity game that loses focus and gets it back (Cmd-Tab, a click on another
# app, an app that brings itself forward) keeps drawing but drops every key and click (Chants of Sennaar,
# 2026-10-31). Sikarugir's revision 6 has no public source, so the fix is three byte edits to its
# winemac.so, each checked against the bytes it replaces; any other winemac.so stops the build.
#   1. macdrv_window_got_focus: no made-up WM_MOUSEACTIVATE(HTMENU) before activating; straight to
#      "setting foreground window" (Wine b568eaac4a, wine-10.6, Wine bug 48121).
#   2. makeFocused: discard only WINDOW_LOST_FOCUS, not WINDOW_GOT_FOCUS (CrossOver hack 18896).
#   3. windowDidBecomeKey: no early return when Wine itself made the window key (CrossOver hack 18896).
# Highball (github.com/gauthierpiarrette/highball) found and described this fix; the offsets here were
# read from our own disassembly of the same file.
WINEMAC_SHA="4cbf65e363d6d8b5a70dba719b50b811fb4b2705985e93f777c6cb7a12878eb0"
WINEMAC_FIXED_SHA="87cda88afce336cb2fc64b117f9b48142b99b432d35b7fbf07f0facd3bafbfe9"
WINEMAC_EDITS="40d87:4883ec08:eb71 193dc:30:20 1c584:741d:9090"

fix_winemac() {
    local so="$1/wine/lib/wine/x86_64-unix/winemac.so"
    [ "$(shasum -a 256 "$so" | awk '{print $1}')" = "$WINEMAC_SHA" ] || { echo "winemac.so is not the build the focus fix was read from" >&2; return 1; }
    python3 -I - "$so" "$so.new" $WINEMAC_EDITS <<'PY'
import sys
src, dst, *edits = sys.argv[1:]
b = bytearray(open(src, 'rb').read())
for e in edits:
    off, old, new = e.split(':')
    off, old, new = int(off, 16), bytes.fromhex(old), bytes.fromhex(new)
    if bytes(b[off:off + len(old)]) != old:
        sys.exit(f'{off:#x}: expected {old.hex()}, found {b[off:off + len(old)].hex()}')
    b[off:off + len(new)] = new
open(dst, 'wb').write(b)
PY
    local id
    id=$(codesign -dv "$so" 2>&1 | sed -n 's/^Identifier=//p')
    codesign -f -s - -i "$id" "$so.new" 2>/dev/null
    codesign -v "$so.new"
    mv "$so.new" "$so"
}

# Folders the engine's libraries are found in at run time (DYLD_FALLBACK_LIBRARY_PATH).
lib_dirs() {
    local root="$1"
    echo "$root/Frameworks"
    echo "$root/Frameworks/GStreamer.framework/Versions/1.0/lib"
    echo "$root/wine/lib/wine/x86_64-unix"
}

check() {
    local root="$1" missing=0
    while IFS= read -r -d '' f; do
        file -b "$f" | grep -q Mach-O || continue
        while read -r dep; do
            local name="${dep#@rpath/}" found=0
            while read -r dir; do [ -e "$dir/$name" ] && found=1 && break; done < <(lib_dirs "$root")
            if [ $found = 0 ]; then echo "missing: $name (needed by ${f#$root/})"; missing=1; fi
        done < <(otool -L "$f" | awk 'NR>1 {print $1}' | grep '^@rpath/' || true)
    done < <(find "$root/wine" -type f \( -perm -u+x -o -name '*.so' -o -name '*.dylib' \) -print0)
    # Apple's Game Porting Toolkit files, by name. Not all of them say "d3dmetal".
    local apple
    apple=$(find "$root" \( -iname '*d3dmetal*' -o -iname '*apple_gptk*' -o -iname 'libd3dshared*' \
        -o -iname 'atidxx64.dll' -o -iname 'nvngx-on-metalfx*' -o -iname 'libmetalirconverter*' \
        -o -iname 'libdxilconv*' \) -print)
    if [ -n "$apple" ]; then
        echo "Apple Game Porting Toolkit files found in the engine (they must not be redistributed):"
        echo "$apple" | sed "s|^$root/|  |"
        missing=1
    fi
    # By content: with GPTK_REDIST pointing at the toolkit's redist/lib, no engine file may be a copy
    # of one of Apple's, whatever it is called.
    if [ -n "${GPTK_REDIST:-}" ]; then
        local hashes
        hashes=$(find "$GPTK_REDIST" -type f -exec shasum -a 256 {} + | awk '{print $1}' | sort -u)
        while read -r h f; do
            if grep -qx "$h" <<<"$hashes"; then echo "copy of an Apple toolkit file: ${f#$root/}"; missing=1; fi
        done < <(find "$root" -type f \( -iname '*.dll' -o -iname '*.dylib' -o -iname '*.so' \) -exec shasum -a 256 {} +)
    fi
    local mac="$root/wine/lib/wine/x86_64-unix/winemac.so"
    if [ -e "$mac" ] && [ "$(shasum -a 256 "$mac" | awk '{print $1}')" != "$WINEMAC_FIXED_SHA" ]; then
        echo "winemac.so is not the focus-fixed build"; missing=1
    fi
    [ $missing = 0 ] && echo "all dependencies resolve"
    return $missing
}

if [ "${1:-}" = "--check" ]; then check "$2"; exit; fi

work="${1:?usage: package-engine.sh <workdir> | --check <folder>}"
mkdir -p "$work/src" "$work/out"
cd "$work/src"
gh release download v1.0 -R Sikarugir-App/Engines -p "$ENGINE_ASSET" --skip-existing
gh release download v1.0 -R Sikarugir-App/Wrapper -p "$TEMPLATE_ASSET" --skip-existing

rm -rf engine template "$work/out/$ENGINE_ID"
mkdir engine template
tar -xJf "$ENGINE_ASSET" -C engine
tar -xJf "$TEMPLATE_ASSET" -C template
frameworks=$(find template -maxdepth 3 -type d -path '*/Contents/Frameworks' | head -1)

out="$work/out/$ENGINE_ID"
mkdir -p "$out/Frameworks" "$out/renderer"
cp -R engine/wswine.bundle "$out/wine"
fix_winemac "$out"
for item in "$frameworks"/*; do
    case "$(basename "$item")" in renderer|SikarugirSdk.framework) continue ;; esac
    cp -R "$item" "$out/Frameworks/"
done
for r in dxvk d9vk dxmt; do cp -R "$frameworks/renderer/$r" "$out/renderer/$r"; done

cat > "$out/ENGINE.json" <<JSON
{
  "id": "$ENGINE_ID",
  "wineVersion": "$WINE_VERSION",
  "sources": { "engine": "$ENGINE_ASSET", "template": "$TEMPLATE_ASSET" },
  "fixes": ["winemac focus (Wine b568eaac4a, CrossOver hack 18896)"],
  "builtAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON

check "$out"

tarball="$work/out/cellar-engine-$ENGINE_ID.tar.xz"
tar -C "$work/out" -cJf "$tarball" "$ENGINE_ID"
echo "tarball: $tarball"
echo "sha256:  $(shasum -a 256 "$tarball" | awk '{print $1}')"
echo "size:    $(stat -f %z "$tarball")"
