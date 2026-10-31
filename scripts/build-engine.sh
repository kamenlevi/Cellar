#!/bin/bash
# Builds Cellar's own engine from CodeWeavers' public CrossOver source, with Cellar's patches.
#
#   scripts/build-engine.sh <workdir>     download (if needed), build, assemble, check, tar; prints sha256 and size
#
# Runs on an x86_64 Mac (GitHub's macos-15-intel runner, see .github/workflows/engine.yml). Build tools and the
# development files Wine is built against come from Homebrew on that machine; at run time the engine uses the same
# runtime libraries as engine c2, from Sikarugir's wrapper template, so nothing from Homebrew ships.
# D3DMetal is Apple's and is never part of the engine: Cellar loads the user's own import via WINEDLLPATH_PREPEND.
set -euo pipefail

CX_VERSION="25.1.1"
ENGINE_ID="crossover-$CX_VERSION-c1"
SOURCE="crossover-sources-$CX_VERSION.tar.gz"
SOURCE_URL="https://media.codeweavers.com/pub/crossover/source/$SOURCE"
SOURCE_SHA="7cdcfcfaee8991f7958b5ccb2837c0facec6e8e681cd3ada8d2745bddbe27d13"
TEMPLATE_ASSET="Template-1.0.11.tar.xz"
TEMPLATE_SHA="9fa15479e7ff6abd99c1d07be285fb95f41fc6991586502427152b1f7d6ccb8a"
# Wine Mono 9.4.0 and Gecko 2.47.4 (the versions dlls/appwiz.cpl/addons.c asks for) come from Cellar's own c2 engine
# release: the same files as today's engine, pinned by engines.json's checksum. WineHQ publishes no checksums for them.
ADDONS_FROM="sikarugir-10.0_6-c2"
ADDONS_SHA="e16805a0368f1716d3a212b8b4528f37169be3d62271bd9d08065e9b63d9857f"

repo="$(cd "$(dirname "$0")/.." && pwd)"
work="${1:?usage: build-engine.sh <workdir>}"
mkdir -p "$work/dl" "$work/out"
work="$(cd "$work" && pwd)"
jobs="${JOBS:-$(sysctl -n hw.ncpu)}"

[ "$(uname -m)" = x86_64 ] || { echo "build-engine.sh runs on an x86_64 Mac (macos-15-intel)" >&2; exit 1; }

# --- Sources ---------------------------------------------------------------------------------------------------
cd "$work/dl"
[ -f "$SOURCE" ] || curl -fL --retry 3 -o "$SOURCE" "$SOURCE_URL"
[ "$(shasum -a 256 "$SOURCE" | awk '{print $1}')" = "$SOURCE_SHA" ] || { echo "$SOURCE: wrong checksum" >&2; exit 1; }
gh release download v1.0 -R Sikarugir-App/Wrapper -p "$TEMPLATE_ASSET" --skip-existing
[ "$(shasum -a 256 "$TEMPLATE_ASSET" | awk '{print $1}')" = "$TEMPLATE_SHA" ] || { echo "$TEMPLATE_ASSET: wrong checksum" >&2; exit 1; }
addons="cellar-engine-$ADDONS_FROM.tar.xz"
gh release download "engine-$ADDONS_FROM" -R kamenlevi/Cellar -p "$addons" --skip-existing
[ "$(shasum -a 256 "$addons" | awk '{print $1}')" = "$ADDONS_SHA" ] || { echo "$addons: wrong checksum" >&2; exit 1; }

rm -rf "$work/src" && mkdir -p "$work/src"
tar -xzf "$SOURCE" -C "$work/src"
wine_src="$work/src/sources/wine"
for p in "$repo"/engine/patches/crossover-$CX_VERSION/*.patch; do
    echo "patch: $(basename "$p")"
    patch -d "$wine_src" -p1 --forward < "$p"
done

# CrossOver's own build generates include/distversion.h; winedbg's crash dialog needs its two messages.
distversion='/* Written by Cellar'"'"'s scripts/build-engine.sh (CrossOver'"'"'s build generates this file). */
#define WINDEBUG_WHAT_HAPPENED_MESSAGE "This program crashed in Cellar'"'"'s Wine engine."
#define WINDEBUG_USER_SUGGESTION_MESSAGE "The details below can help find out why."'
echo "$distversion" > "$wine_src/include/distversion.h"
echo "$distversion" > "$wine_src/programs/winedbg/distversion.h"   # where makedep resolves winedbg.rc's include

# --- Build -----------------------------------------------------------------------------------------------------
brew_prefix="$(brew --prefix)"
export PATH="$brew_prefix/opt/bison/bin:$brew_prefix/opt/flex/bin:$PATH"
export PKG_CONFIG_PATH="$brew_prefix/lib/pkgconfig:$brew_prefix/opt/gnutls/lib/pkgconfig:$brew_prefix/opt/freetype/lib/pkgconfig"
export CPPFLAGS="-I$brew_prefix/include"
export LDFLAGS="-L$brew_prefix/lib"
export MACOSX_DEPLOYMENT_TARGET=11.0
# ccache: most of Wine is its Windows-side code (~7,600 of ~8,000 compiles), so the mingw compilers go through it too.
cross=()
if command -v ccache >/dev/null; then
    export CC="ccache clang" CXX="ccache clang++" CCACHE_MAXSIZE=8G
    cross=(i386_CC="ccache i686-w64-mingw32-gcc" x86_64_CC="ccache x86_64-w64-mingw32-gcc")
fi

out="$work/out/$ENGINE_ID"
rm -rf "$out" "$work/build" && mkdir -p "$out" "$work/build/include"
# Wine's dependency scanner looks for generated headers in the build tree.
echo "$distversion" > "$work/build/include/distversion.h"
cd "$work/build"
"$wine_src/configure" \
    --prefix="$out/wine" \
    --enable-archs=i386,x86_64 \
    --with-mingw=x86_64-w64-mingw32-gcc \
    --with-coreaudio --with-freetype --with-gnutls --with-gstreamer --with-sdl --with-vulkan \
    --without-x --without-oss --without-alsa --without-pulse --without-cups --without-sane --without-gphoto \
    --without-krb5 --without-netapi --without-pcap --without-v4l2 --without-wayland --without-dbus \
    --disable-tests \
    ${cross[@]+"${cross[@]}"} \
    ac_cv_lib_soname_odbc=   # as in engine c2: Wine asks for plain libodbc.dylib, and works without it
make -j"$jobs"
make install-lib

# Every library Wine opens by name at run time must be one the engine ships (Sikarugir's template), or one engine c2
# also asks for without shipping it (Wine runs on without it).
optional="libodbc.dylib"
template="$work/template" && rm -rf "$template" && mkdir -p "$template"
tar -xJf "$work/dl/$TEMPLATE_ASSET" -C "$template"
frameworks=$(find "$template" -maxdepth 3 -type d -path '*/Contents/Frameworks' | head -1)
missing=0
while read -r soname; do
    [[ " $optional " == *" $soname "* ]] || [ -e "$frameworks/$soname" ] || [ -e "/usr/lib/$soname" ] || [ -e "/System/Library/Frameworks/${soname%%.*}.framework" ] \
        || { echo "Wine opens $soname, which the template doesn't ship"; missing=1; }
done < <(sed -n 's/^#define SONAME_LIB[A-Z0-9_]* "\(.*\)"$/\1/p' include/config.h)
[ $missing = 0 ] || exit 1

# --- Assemble (the same layout as package-engine.sh's) ----------------------------------------------------------
mkdir -p "$out/Frameworks" "$out/renderer" "$out/wine/share/wine/mono" "$out/wine/share/wine/gecko"
for item in "$frameworks"/*; do
    case "$(basename "$item")" in renderer|SikarugirSdk.framework) continue ;; esac
    cp -R "$item" "$out/Frameworks/"
done
for r in dxvk d9vk dxmt; do cp -R "$frameworks/renderer/$r" "$out/renderer/$r"; done
tar -xJf "$work/dl/$addons" -C "$out/wine/share/wine" --strip-components 4 \
    "$ADDONS_FROM/wine/share/wine/mono" "$ADDONS_FROM/wine/share/wine/gecko"

patches=$(cd "$repo/engine/patches/crossover-$CX_VERSION" && ls *.patch | sed 's/.*/"&"/' | paste -sd, -)
cat > "$out/ENGINE.json" <<JSON
{
  "id": "$ENGINE_ID",
  "wineVersion": "$(cat "$wine_src/VERSION" | sed 's/Wine version //') (CrossOver $CX_VERSION)",
  "source": "$SOURCE",
  "patches": [$patches],
  "sources": { "template": "$TEMPLATE_ASSET", "monoAndGecko": "engine-$ADDONS_FROM" },
  "builtAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON

"$repo/scripts/package-engine.sh" --check "$out"

tarball="$work/out/cellar-engine-$ENGINE_ID.tar.xz"
tar -C "$work/out" -cJf "$tarball" "$ENGINE_ID"
echo "tarball: $tarball"
echo "sha256:  $(shasum -a 256 "$tarball" | awk '{print $1}')"
echo "size:    $(stat -f %z "$tarball")"
