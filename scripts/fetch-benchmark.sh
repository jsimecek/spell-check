#!/usr/bin/env bash
# Downloads pinned English misspelling lists into Benchmarks/ for the opt-in benchmark
# (Tests/SpellCoreTests/BenchmarkTests.swift). Test-only data, fetched, never committed or shipped.
# Usage: scripts/fetch-benchmark.sh   (skips anything already present and verified)
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="Benchmarks"
CURL=(curl -sSfL --proto '=https' --tlsv1.2)

# "file url sha256"
FILES=(
  "wikipedia-misspellings.txt https://en.wikipedia.org/w/index.php?oldid=1199637275&action=raw 3b6a9290e5aaad968da7ec769a5174adb45247688ef7ae097fd2dd80237a3050"
  "aspell.dat https://www.dcs.bbk.ac.uk/~ROGER/aspell.dat 0198fa5c343f82f0541ae39a0116b534e14bfadc54144377cadee2bd6d288988"
)

mkdir -p "$DEST"

for entry in "${FILES[@]}"; do
  read -r name url sha <<<"$entry"
  file="$DEST/$name"
  if [[ -f "$file" ]] && echo "$sha  $file" | shasum -a 256 -c --status; then
    continue
  fi
  "${CURL[@]}" -o "$file.tmp" "$url" || { rm -f "$file.tmp"; echo "Download failed: $url" >&2; exit 1; }
  echo "$sha  $file.tmp" | shasum -a 256 -c --status || { rm -f "$file.tmp"; echo "Checksum mismatch: $url" >&2; exit 1; }
  mv "$file.tmp" "$file"
done

echo "Benchmark data ready in $DEST/"
