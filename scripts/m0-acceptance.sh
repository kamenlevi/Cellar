#!/bin/bash
# M0 "done when": a fresh user gets a working bottle from Cellar alone — the engine comes from
# Cellar's own GitHub release, and nothing from Sikarugir, Heroic or Homebrew is used.
# Runs headless (no windows, no sound) in a throwaway CELLAR_HOME, which it leaves for inspection.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release -j 4
cellar="$PWD/.build/release/cellar"
root=$(mktemp -d -t cellar-m0)

# A clean environment: no Homebrew on PATH, nothing inherited from this shell.
clean() { env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin CELLAR_HOME="$root" "$@"; }

echo "== cellar doctor (before install)"
clean "$cellar" doctor || true
echo "== cellar engine install"
clean "$cellar" engine install
echo "== cellar bottle create \"M0 Check\""
clean "$cellar" bottle create "M0 Check"
echo "== cellar run --headless \"M0 Check\" cmd /c echo cellar-ok"
output=$(clean "$cellar" run --headless "M0 Check" cmd /c echo cellar-ok)
echo "$output"
grep -q cellar-ok <<<"$output"
clean "$cellar" bottle kill "M0 Check"

echo
echo "M0 acceptance: PASS"
echo "Throwaway root left at: $root"
