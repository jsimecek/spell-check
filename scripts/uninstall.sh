#!/usr/bin/env bash
# Removes CzEnSpell.service and restores the native spell checker list.
set -euo pipefail

DEST="$HOME/Library/Services/CzEnSpell.service"
pkill -x CzEnSpell 2>/dev/null || true
rm -rf "$DEST"
/System/Library/CoreServices/pbs -update
echo "Removed $DEST"
echo "Set System Settings > Keyboard > Text Input > Edit > Spelling back to 'Automatic by Language'."
