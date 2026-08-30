#!/usr/bin/env bash
#
# Packages the mod for distribution.
#
#   tools/build.sh            -> dist/ERLeveling/
#   tools/build.sh --zip      -> the same, plus a .zip archive
#
# The shipped folder carries both layouts at once: Build 41 reads the root
# media/, Build 42 reads the 42/ subfolder. tools/sync_versioned.sh generates
# and verifies that subfolder from the root tree, which stays the single source
# of truth.
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

# --- Packaged copy ---------------------------------------------------------
# The shipped folder already carries both layouts, so packaging is a straight
# copy: Build 41 reads the root media/, Build 42 reads 42/media/.
echo "==> packaging"
OUT="$DIST/ERLeveling/Contents/mods/ERLeveling"
mkdir -p "$OUT"
cp -r "$SRC/." "$OUT/"
echo "    $OUT"

# --- Build 42: versioned layout -------------------------------------------
# Both trees are committed (see tools/sync_versioned.sh for why), so this only
# has to confirm the generated one has not drifted from its source.
# --- static lints ----------------------------------------------------------
# Both of these encode bugs that actually shipped; see NOTES.md.
echo "==> static lints"

# 1. Kahlua cannot index the object a Class-name lookup returns. The call throws,
#    a pcall catches it, and Project Zomboid logs a full stack trace anyway - on
#    a per-tick path that buries console.txt at frame rate.
if grep -rn ":getClass(" "$SRC/media/lua" >/dev/null 2>&1; then
    echo "    FAIL: a Class-name lookup is back in the source:" >&2
    grep -rn ":getClass(" "$SRC/media/lua" >&2
    exit 1
fi
echo "    no Class-name lookups"

# 2. client/UI loads alphabetically, so any file sorting before ERUI.lua that
#    touches ERUI at file scope errors out and takes its whole file with it -
#    which is how the Runes tab and the rune strip once vanished entirely.
lint_fail=0
for f in "$SRC"/media/lua/client/UI/*.lua; do
    base="$(basename "$f")"
    if [[ "$base" < "ERUI.lua" ]] && grep -q "^ERUI\." "$f"; then
        echo "    FAIL: $base uses ERUI at file scope but loads before ERUI.lua" >&2
        lint_fail=1
    fi
done
[ "$lint_fail" = "0" ] || exit 1
echo "    no file-scope use of ERUI before it loads"

echo "==> checking the Build 42 subtree"
"$ROOT/tools/sync_versioned.sh" --check

if [ "${1:-}" = "--zip" ]; then
    if command -v zip >/dev/null 2>&1; then
        echo "==> zipping"
        (cd "$DIST/ERLeveling" && zip -qr "../ERLeveling.zip" .)
        echo "    $DIST/ERLeveling.zip"
    else
        echo "    (zip not installed, skipping archives)"
    fi
fi

echo "==> done"
