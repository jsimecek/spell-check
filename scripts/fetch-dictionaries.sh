#!/usr/bin/env bash
# Downloads pinned Hunspell dictionaries (LibreOffice, cs_CZ is GPL), word frequency lists
# (hermitdave/FrequencyWords, CC-BY-SA 4.0) and builds n-gram models from Leipzig web corpora
# (CC BY / BY-NC, personal use). Third-party data is fetched, not committed.
set -euo pipefail
cd "$(dirname "$0")/.."

LIBREOFFICE="https://raw.githubusercontent.com/LibreOffice/dictionaries/67032ee957631908098a72edf48dc81cac27e369"
FREQUENCY="https://raw.githubusercontent.com/hermitdave/FrequencyWords/525f9b560de45753a5ea01069454e72e9aa541c6/content/2018"
DEST="Dictionaries"

FILES=(
  "$LIBREOFFICE/cs_CZ/cs_CZ.aff 7ecb20620ecd46ebd9c36f3f33e69dd4eda385cba5b2bb4e6bc396d910e297f7"
  "$LIBREOFFICE/cs_CZ/cs_CZ.dic d8e8c88c006fdae72dac8c85df11b0c99a773e05a4ab0fcbe92244876668ca74"
  "$LIBREOFFICE/en/en_US.aff e746c882dd6f303c2c46e7452804b9201115a6942cfeb15f18f8edf774d2e24e"
  "$LIBREOFFICE/en/en_US.dic f0b1a234bd178bdd01875b2a392a9647f888b8fe879f79c52aae62c2759b3647"
  "$FREQUENCY/cs/cs_50k.txt 1fb0576ef07cf5a543789d394cde1168573fc9e7adf427fd143249fd5547458d"
  "$FREQUENCY/en/en_50k.txt 5351ff405b1126ef555791dd4d9798a48e3e9a501a9fc481a9da957752cfb458"
)

mkdir -p "$DEST"
for entry in "${FILES[@]}"; do
  read -r url sha <<<"$entry"
  file="$DEST/$(basename "$url")"
  if [[ -f "$file" ]] && echo "$sha  $file" | shasum -a 256 -c --status; then
    continue
  fi
  curl -sSfL -o "$file.tmp" "$url"
  echo "$sha  $file.tmp" | shasum -a 256 -c --status || { rm -f "$file.tmp"; echo "Checksum mismatch: $url" >&2; exit 1; }
  mv "$file.tmp" "$file"
done
LEIPZIG="https://downloads.wortschatz-leipzig.de/corpora"
# Bump when ngram-build output changes for the same corpus and options.
MODEL_REV=2
CORPORA=(
  "cs ces-cz_web-public_2019_1M f1ef7a5b76fc0db58a926f612c533b0cd3d75d5b64b649eebb9fdcbf2b6fde66 2 --skip-unaccented"
  "en eng-com_web-public_2018_1M de8849fe30c7d5bf3502f620093232f4dceca10a6ac19a9ad49f474b62df0a5f 2"
)
for entry in "${CORPORA[@]}"; do
  read -r lang corpus sha options <<<"$entry"
  model="$DEST/$lang.ngram"
  # Rebuild when the build options change; the sidecar records what the model was built with.
  [[ -f "$model" && "$(cat "$model.options" 2>/dev/null)" == "$corpus $options rev$MODEL_REV" ]] && continue
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  echo "Building $model from $corpus (~200 MB download)..."
  curl -sSfL -o "$tmp/corpus.tar.gz" "$LEIPZIG/$corpus.tar.gz"
  echo "$sha  $tmp/corpus.tar.gz" | shasum -a 256 -c --status || { echo "Checksum mismatch: $corpus" >&2; exit 1; }
  tar -xzf "$tmp/corpus.tar.gz" -C "$tmp" "$corpus/$corpus-sentences.txt"
  swift build -c release --product ngram-build >/dev/null
  # shellcheck disable=SC2086
  .build/release/ngram-build "$tmp/$corpus/$corpus-sentences.txt" "$model.tmp" $options
  mv "$model.tmp" "$model"
  echo "$corpus $options rev$MODEL_REV" > "$model.options"
  rm -rf "$tmp"
done

echo "Dictionaries ready in $DEST/"
