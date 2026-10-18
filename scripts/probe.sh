#!/usr/bin/env bash
# Runs scripts/probe-sentences.txt through NSSpellChecker the way a real app does.
# Usage: scripts/probe.sh [mul|auto|cs|en]
#   mul (default) is CzEnSpell, auto is macOS automatic language identification, cs/en are Apple's own.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product spellprobe >/dev/null
.build/release/spellprobe "${1:-mul}" < scripts/probe-sentences.txt
