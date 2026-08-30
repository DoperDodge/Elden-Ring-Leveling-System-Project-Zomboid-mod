#!/usr/bin/env bash
#
# Mirrors the Build 41 tree at Contents/mods/ERLeveling into the Build 42
# versioned subfolder Contents/mods/ERLeveling/42.
#
#   tools/sync_versioned.sh           refresh 42/ from the root tree
#   tools/sync_versioned.sh --check   fail if 42/ has drifted (used by build.sh)
#
# WHY BOTH TREES ARE COMMITTED
# ----------------------------
# Build 41 reads a mod's root media/ folder and ignores version subfolders.
# Build 42 prefers a 42/ subfolder when one is present. Shipping only the flat
# layout means Build 42 users can have the mod filtered out of the mod list as
# an untagged legacy mod. Shipping both means whichever build you are on finds
# a tree with a matching pzversion, and the person installing it does not have
# to run a build step first.
#
# The root tree is the single source of truth. 42/ is generated. Never hand-edit
# anything under 42/ - edit the root tree and re-run this.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOD="$ROOT/Contents/mods/ERLeveling"
V42="$MOD/42"

if [ ! -d "$MOD/media" ]; then
    echo "error: $MOD/media not found" >&2
    exit 1
fi

if [ "${1:-}" = "--check" ]; then
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    cp -r "$MOD/media" "$TMP/media"
    cp "$MOD/poster.png" "$TMP/poster.png"
    if diff -r -q "$TMP/media" "$V42/media" >/dev/null 2>&1 \
       && diff -q "$TMP/poster.png" "$V42/poster.png" >/dev/null 2>&1; then
        echo "    42/ is in sync with the root tree"
        exit 0
    fi
    echo "    42/ HAS DRIFTED from the root tree - run tools/sync_versioned.sh" >&2
    exit 1
fi

rm -rf "$V42/media"
mkdir -p "$V42"
cp -r "$MOD/media" "$V42/media"
cp "$MOD/poster.png" "$V42/poster.png"
echo "synced $V42/media and poster.png from the root tree"
echo "note: 42/mod.info is maintained by hand (it carries its own pzversion)"
