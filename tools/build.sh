#!/usr/bin/env bash
#
# Packages the mod for distribution.
#
#   tools/build.sh            -> dist/ERLeveling-b41/  and  dist/ERLeveling-b42/
#   tools/build.sh --zip      -> the same, plus .zip archives
#
# The single source of truth is Contents/mods/ERLeveling/media. Build 41 reads a
# mod's media/ folder directly; Build 42 prefers a versioned 42/ subfolder when
# one is present. Rather than keeping two copies of every Lua file in git, the
# Build 42 layout is generated here.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/Contents/mods/ERLeveling"
DIST="$ROOT/dist"

if [ ! -d "$SRC" ]; then
    echo "error: $SRC not found" >&2
    exit 1
fi

echo "==> validating Lua"
if command -v luac5.4 >/dev/null 2>&1; then
    LUAC=luac5.4
elif command -v luac >/dev/null 2>&1; then
    LUAC=luac
else
    LUAC=""
    echo "    (no luac on PATH, skipping the syntax check)"
fi
if [ -n "$LUAC" ]; then
    find "$SRC/media/lua" -name '*.lua' -print0 | xargs -0 -n1 "$LUAC" -p
    echo "    all Lua files parse"
fi

if command -v lua5.4 >/dev/null 2>&1; then
    echo "==> running the offline test suite"
    (cd "$ROOT" && lua5.4 tools/test_offline.lua >/dev/null) \
        && echo "    tests pass" \
        || { echo "    TESTS FAILED - run 'lua5.4 tools/test_offline.lua' for detail" >&2; exit 1; }
fi

rm -rf "$DIST"
mkdir -p "$DIST"

# --- Build 41: flat layout -------------------------------------------------
echo "==> building Build 41 layout"
B41="$DIST/ERLeveling-b41/Contents/mods/ERLeveling"
mkdir -p "$B41"
cp -r "$SRC/." "$B41/"
echo "    $B41"

# --- Build 42: versioned layout -------------------------------------------
echo "==> building Build 42 layout"
B42="$DIST/ERLeveling-b42/Contents/mods/ERLeveling"
mkdir -p "$B42/42"
cp "$SRC/mod.info" "$B42/mod.info"
cp "$SRC/poster.png" "$B42/poster.png"
cp "$SRC/README.txt" "$B42/README.txt"
cp "$SRC/mod.info" "$B42/42/mod.info"
cp -r "$SRC/media" "$B42/42/media"
echo "    $B42"

if [ "${1:-}" = "--zip" ]; then
    if command -v zip >/dev/null 2>&1; then
        echo "==> zipping"
        (cd "$DIST/ERLeveling-b41" && zip -qr "../ERLeveling-b41.zip" .)
        (cd "$DIST/ERLeveling-b42" && zip -qr "../ERLeveling-b42.zip" .)
        echo "    $DIST/ERLeveling-b41.zip"
        echo "    $DIST/ERLeveling-b42.zip"
    else
        echo "    (zip not installed, skipping archives)"
    fi
fi

echo "==> done"
