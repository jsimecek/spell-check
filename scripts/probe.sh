#!/usr/bin/env bash
# Runs scripts/probe-sentences.txt through NSSpellChecker for a language id.
# `scripts/probe.sh` checks CzEnSpell (mul), `scripts/probe.sh auto` the native automatic mode, `scripts/probe.sh cs` Apple Czech only.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product spellprobe >/dev/null
.build/release/spellprobe "${1:-mul}" < scripts/probe-sentences.txt
