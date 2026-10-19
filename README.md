# CzEnSpell

Czech + English spell checking for macOS, as a native system spell service. It appears in the Spelling setting as **Multiple languages (CzEnSpell)** and checks both languages at once, so mixed text like "pošli mi ten pull request" is fine while "muzes" and "teh" get underlined with the right suggestions. Apps keep the normal red squiggle and right-click suggestions.

## Why

On macOS 27 the built-in checker underlines Czech words but often offers no suggestions. Apple's Czech dictionary is fine (`scripts/probe.sh cs`); the problem is automatic language detection. Czech typed without accents is often detected as `und` (undetermined), and then no dictionary offers suggestions. Output of `scripts/probe.sh auto` vs `scripts/probe.sh mul` on macOS 27.0.1 with English and Czech enabled:

| Input | Native "Automatic by Language" | CzEnSpell |
|---|---|---|
| `Ahoj, prosim te muzes mi to poslat?` | `und`: 3 words underlined, no suggestions | `prosím`, `tě`, `můžeš` |
| `Zitra pujdeme do kina s kamarady.` | `und`: 3 words underlined, no suggestions | `Zítra`, `půjdeme`, `kamarády` |
| `To je dobrej napad, kterej jsi mel, ted to vim.` | `und`: 6 words underlined, no suggestions | `dobrý`, `nápad`, `který`, `měl` |

With many languages enabled it gets worse: in earlier runs with about 34 languages, some misspellings (`teh`, `nevim`) were not underlined at all.

## Requirements

- macOS 14 or later to run. Tested on macOS 27.0.1 only.
- Xcode with Swift 6 to build (`swift-tools-version:6.0`). Developed with Xcode 27.0 (Swift 6.4).
- Network access for the first build, which downloads dictionaries and two text corpora of about 200 MB each.

There are no prebuilt binaries. You build the service on your own Mac.

## Install

```sh
git clone https://github.com/jsimecek/spell-check
cd spell-check
scripts/build.sh      # first run downloads data (a few minutes), builds build/CzEnSpell.service
scripts/install.sh    # copies it to ~/Library/Services (current user only, no sudo)
```

Then turn it on:

1. Open **System Settings > Keyboard**. Under **Text Input**, click **Edit…** next to **Input Sources**.
2. Select **All Input Sources**, set **Spelling** to **Multiple languages (CzEnSpell)** and turn off **Correct spelling automatically**.
3. Restart apps that were already running. They keep the old checker until then.

Optional check: `scripts/probe.sh` runs sample sentences through the system checker the way an app does. The first run after install may report no misspellings while the service starts; run it again.

## Uninstall

```sh
scripts/uninstall.sh
```

Then set **Spelling** back to **Automatic by Language** in the same settings sheet.

## How it works

- The service registers the language `mul` with macOS through `NSSpellServer`. Apps that use the system checker (Cocoa text views, WebKit in Safari and Mail) send their spelling requests to it.
- A word is correct if the Czech or the English Hunspell dictionary accepts it. In Czech text, an English-only word with a valid accented Czech form (`ted`, `vim`, `problem`) is still flagged.
- Each sentence is classified as Czech or English by how common its words are in each language (Czech typed without accents counts as its accented form), with Apple's `NLLanguageRecognizer` as the tie-breaker.
- Suggestions come from Hunspell, accent restoration (`muzes` → `můžeš`), standard forms of spoken Czech (`kterej` → `který`), near-miss common words, and Apple's own cs/en dictionaries (asked by a helper process, because Apple's checker stalls when called from inside a spell service).
- A word-pair model built from the Leipzig corpora ranks suggestions by how well they fit between the neighbouring words, so `prosim te` suggests `tě` and `mam praci` suggests `práci`.
- Typical slips cost less than random edits: a left-out accent is free, an accent you typed counts, and i/y, the y/z keyboard-layout swap, doubled letters and swapped letters are cheap.
- In Czech sentences, a valid word that is missing accents is flagged when the accented form fits much better (`Nemam cas` → `Nemám čas`). A rare correct word is occasionally flagged; that is the accepted trade-off.
- At most 5 suggestions. It only underlines and suggests, it never replaces text on its own.

## Privacy

- Everything runs locally. CzEnSpell's code makes no network requests; only `scripts/fetch-dictionaries.sh` downloads data, at build time.
- Logs (unified log, subsystem `io.github.jsimecek.CzEnSpell`) contain counts, timings and error codes, never the checked text.
- Words you add with "Learn Spelling" are saved in `~/Library/Application Support/CzEnSpell/learned.txt`. Words already learned in macOS (`~/Library/Spelling/LocalDictionary`) are read, never written.

## Limitations

- The bundle is ad-hoc signed for the Mac that built it and is not notarized.
- Apps with their own spell checker (Firefox, Microsoft Office) are not affected. Chromium and Electron apps are untested.
- Knows only Czech and English: most words in other languages are underlined.
- No grammar checking. Real-word mistakes are only caught when accents are missing (`byt`/`být` is judged on accents, never on grammar).
- Right after install or a crash, the first check can come back empty while the service starts. The next check works.
- Memory: about 100 MB for the service plus about 30 MB for the helper.

## Development

```sh
scripts/fetch-dictionaries.sh   # required once before swift test
swift build
swift test                      # unit tests plus integration tests against the real dictionaries
scripts/fetch-benchmark.sh      # optional: English misspelling lists and news sentences for the quality benchmark
CZEN_EVAL=1 swift test -c release -Xswiftc -enable-testing --filter BenchmarkTests
```

End-to-end check on your Mac: `scripts/build.sh`, `scripts/install.sh`, then `scripts/probe.sh mul` twice (the first run warms up the service). `scripts/probe.sh auto`, `cs` and `en` show what the native checker does for comparison.

Design notes and hard-won macOS constraints are in [AGENTS.md](AGENTS.md).

## License

The code in this repository is [MIT](LICENSE) licensed. Third-party parts keep their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). In short:

- Vendored [Hunspell](https://github.com/hunspell/hunspell) 1.7.5 in `Sources/CHunspell`: MPL 1.1 / GPL 2.0+ / LGPL 2.1+.
- Not in this repository, downloaded at build time and copied into the built bundle: the Czech Hunspell dictionary (GPL), the English Hunspell dictionary (SCOWL license), word frequency lists (CC BY-SA 4.0) and word-pair counts derived from the Leipzig Corpora Collection (CC BY, with a non-commercial clause on their terms page).

A bundle you build contains that data, so if you share it, those licenses apply too.

This project does not accept contributions. Forks are welcome under the license.
