#!/usr/bin/env bash
# Builds build/CzEnSpell.service (ad-hoc signed, for this Mac only).
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE="build/CzEnSpell.service"

scripts/fetch-dictionaries.sh
swift build -c release --product CzEnSpellServer
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources/Dictionaries"
cp .build/release/CzEnSpellServer "$BUNDLE/Contents/MacOS/CzEnSpell"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
cp Dictionaries/*.aff Dictionaries/*.dic Dictionaries/*_50k.txt Dictionaries/*.ngram "$BUNDLE/Contents/Resources/Dictionaries/"
plutil -lint "$BUNDLE/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$BUNDLE"
codesign --verify "$BUNDLE"
echo "Built $BUNDLE"
