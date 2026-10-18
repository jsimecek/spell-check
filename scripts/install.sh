#!/usr/bin/env bash
# Installs build/CzEnSpell.service for the current user only (~/Library/Services).
# Usage: scripts/install.sh   (after scripts/build.sh)
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="build/CzEnSpell.service"
SERVICES="${HOME:?}/Library/Services"
DEST="$SERVICES/CzEnSpell.service"
[[ -d "$SRC" ]] || { echo "Run scripts/build.sh first" >&2; exit 1; }

# Stop the old server; macOS launches the new one on the next spell check.
pkill -x -u "$(id -u)" CzEnSpell 2>/dev/null || true
mkdir -p "$SERVICES"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"
/System/Library/CoreServices/pbs -update
echo "Installed $DEST"
