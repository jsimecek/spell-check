#!/usr/bin/env bash
# Removes CzEnSpell.service for the current user and refreshes the list of spell checkers.
# Usage: scripts/uninstall.sh
set -euo pipefail

DEST="${HOME:?}/Library/Services/CzEnSpell.service"

pkill -x -u "$(id -u)" CzEnSpell 2>/dev/null || true
rm -rf "$DEST"
/System/Library/CoreServices/pbs -update
echo "Removed $DEST"
echo "Set System Settings > Keyboard > Text Input > Edit > Spelling back to 'Automatic by Language'."
