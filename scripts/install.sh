#!/usr/bin/env bash
# Installs the built CzEnSpell.service for the current user only.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="build/CzEnSpell.service"
DEST="$HOME/Library/Services/CzEnSpell.service"
[[ -d "$SRC" ]] || { echo "Run scripts/build.sh first" >&2; exit 1; }

pkill -x CzEnSpell 2>/dev/null || true
mkdir -p "$HOME/Library/Services"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"
/System/Library/CoreServices/pbs -update
echo "Installed $DEST"
