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
#
# Build 42 changed this: it expects a version folder ("42") holding mod.info,
# poster.png AND media, alongside a "common" folder that must exist even when it
# is empty. A mod with media/ only at the root does not appear in the Build 42
# mod list at all - no error, no warning, it is simply absent. That is the bug
# this script exists to prevent.
#
# So the shipped folder carries both: the root tree for Build 41, the 42/ tree
# for Build 42, and an occupied common/ folder. The person installing it copies
# one folder and it works on either build with no build step.
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
    ok=1
    diff -r -q "$TMP/media" "$V42/media" >/dev/null 2>&1 || ok=0
    diff -q "$TMP/poster.png" "$V42/poster.png" >/dev/null 2>&1 || ok=0
    diff -q "$MOD/mod.info" "$V42/mod.info" >/dev/null 2>&1 || ok=0
    # git cannot track an empty directory, so common/ must hold a real file or
    # it will not survive a clone - and Build 42 needs the folder to exist.
    [ -f "$MOD/common/README.txt" ] || { echo "    common/ is missing its placeholder file" >&2; ok=0; }
    if [ "$ok" = "1" ]; then
        echo "    42/ is in sync, common/ present"
        exit 0
    fi
    echo "    42/ HAS DRIFTED from the root tree - run tools/sync_versioned.sh" >&2
    exit 1
fi

rm -rf "$V42/media"
mkdir -p "$V42" "$MOD/common"
cp -r "$MOD/media" "$V42/media"
cp "$MOD/poster.png" "$V42/poster.png"
cp "$MOD/mod.info" "$V42/mod.info"
if [ ! -f "$MOD/common/README.txt" ]; then
    echo "warning: $MOD/common/README.txt is missing - Build 42 needs common/ to" >&2
    echo "         exist, and git will not carry an empty directory." >&2
fi
echo "synced $V42/{media,poster.png,mod.info} from the root tree"
