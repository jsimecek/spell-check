#!/usr/bin/env bash
# Downloads pinned English misspelling lists and held-out Leipzig news sentences (CC BY) into
# Benchmarks/ for the opt-in benchmark (Tests/SpellCoreTests/BenchmarkTests.swift).
# Test-only data, fetched, never committed or shipped.
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

# News, not the web corpora the n-gram models are built from, so the benchmark text is unseen.
# "corpus sha256"
CORPORA=(
  "ces_news_2022_30K bdda4532027eb10f6e040ac0127ce53560d944029e63be2b47ad301dcc1285e0"
  "eng_news_2023_30K 59203162b5c6c42c776b990c6913eed0eb4aaf3ac5edca9b98fbf511c19545a6"
)

for entry in "${CORPORA[@]}"; do
  read -r corpus sha <<<"$entry"
  file="$DEST/$corpus-sentences.txt"
  [[ -f "$file" ]] && continue
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  url="https://downloads.wortschatz-leipzig.de/corpora/$corpus.tar.gz"
  "${CURL[@]}" -o "$tmp/corpus.tar.gz" "$url" || { echo "Download failed: $url" >&2; exit 1; }
  echo "$sha  $tmp/corpus.tar.gz" | shasum -a 256 -c --status || { echo "Checksum mismatch: $url" >&2; exit 1; }
  tar -xzf "$tmp/corpus.tar.gz" -C "$tmp" "$corpus/$corpus-sentences.txt"
  mv "$tmp/$corpus/$corpus-sentences.txt" "$file"
  rm -rf "$tmp"
done

echo "Benchmark data ready in $DEST/"
