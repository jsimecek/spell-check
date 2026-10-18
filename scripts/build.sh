#!/usr/bin/env bash
# Builds build/CzEnSpell.service, ad-hoc signed for this Mac only.
# Usage: scripts/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE="build/CzEnSpell.service"
CONTENTS="$BUNDLE/Contents"

scripts/fetch-dictionaries.sh
swift build -c release --product CzEnSpellServer

rm -rf "$BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources/Dictionaries"
cp .build/release/CzEnSpellServer "$CONTENTS/MacOS/CzEnSpell"
cp Resources/Info.plist "$CONTENTS/Info.plist"
cp Dictionaries/*.aff Dictionaries/*.dic Dictionaries/*_50k.txt Dictionaries/*.ngram "$CONTENTS/Resources/Dictionaries/"
plutil -lint "$CONTENTS/Info.plist"

codesign --force --sign - --options runtime --timestamp=none "$BUNDLE"
codesign --verify "$BUNDLE"
echo "Built $BUNDLE"
