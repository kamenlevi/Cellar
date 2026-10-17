#!/bin/bash
# Builds Cellar's engine tarball from Sikarugir's public engine and wrapper template.
#
#   scripts/package-engine.sh <workdir>          download, assemble, tar, print sha256 and size
#   scripts/package-engine.sh --check <folder>   verify every @rpath dependency resolves
#
# D3DMetal is Apple's and may not be redistributed: it is left out, and the build fails if
# anything named d3dmetal or apple_gptk ends up in the output.
set -euo pipefail

ENGINE_ID="sikarugir-10.0_6-c1"
WINE_VERSION="10.0 (Sikarugir revision 6)"
ENGINE_ASSET="WS12WineSikarugir10.0_6.tar.xz"
TEMPLATE_ASSET="Template-1.0.11.tar.xz"

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
    if find "$root" -iname '*d3dmetal*' -o -iname '*apple_gptk*' | grep -q .; then
        echo "D3DMetal found in the engine: it must not be redistributed"; missing=1
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
  "builtAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON

check "$out"

tarball="$work/out/cellar-engine-$ENGINE_ID.tar.xz"
tar -C "$work/out" -cJf "$tarball" "$ENGINE_ID"
echo "tarball: $tarball"
echo "sha256:  $(shasum -a 256 "$tarball" | awk '{print $1}')"
echo "size:    $(stat -f %z "$tarball")"
