# CzEnSpell

Czech + English spell checking for macOS, built as a native spell service. It keeps the system squiggle and the right-click suggestions and replaces the macOS checker, so the two can't clash.

## Why

On macOS 27 the native checker underlines Czech words but often offers no suggestions. Probing `NSSpellChecker` directly (`scripts/probe.sh auto` vs `scripts/probe.sh cs`) shows Apple's Czech dictionary is fine. The problem is **automatic language detection** across ~34 enabled languages:

| Input | Native "Automatic by Language" | CzEnSpell |
|---|---|---|
| `Zitra pujdeme do kina s kamarady.` | detected as `und`, `pujdeme` gets **no suggestions** | `Zítra`, `půjdeme`, `kamarády` |
| `Ahoj, prosim te muzes mi to poslat?` | nothing flagged | `prosím`, `tě`, `můžeš` |
| `Dneska nevim jestli zitra prijdu…` | `nevim`, `zitra` not flagged | all flagged, correct first guess |
| `I definately recieve teh mail` | `teh` not flagged | `the` |

This has nothing to do with Apple Intelligence: Czech isn't an Apple Intelligence language, and Apple Intelligence doesn't drive the squiggles.

## How it works

- Registers language `mul` from vendor `CzEnSpell` via `NSSpellServer`. Apps that use the system checker (Cocoa text views, WebKit in Safari/Mail) route spelling to it. Chromium/Electron apps keep their own language settings, so they're unverified.
- A word is correct if the Czech **or** the English Hunspell dictionary accepts it, so mixed text like "pošli mi pull request" stays clean. In Czech text, an English-only word with a valid accented Czech form (`ted`, `vim`, `problem`) is still flagged.
- **Language per sentence**: Apple's `NLLanguageRecognizer` (restricted to cs/en), overruled by dictionary evidence when unsure. Words that only make sense as Czech without accents count as Czech evidence.
- **Candidates** come from Hunspell, accent restoration (`muzes` → `můžeš`), spoken-Czech standard forms (`kterej` → `který`), near-miss common words, and Apple's own cs/en lists. Apple's lists are fetched in the background by a helper process (`CzEnSpell --apple-helper`), because Apple's checker stalls when called from inside a spell service.
- **Ranking by sentence context**: a word-pair (bigram) model built from Leipzig web corpora scores how well each candidate fits between its neighbours, minus a penalty per real edit (accent-only changes are free) and a penalty for the other language. So `prosim te` → `tě`, `s praci` → `prací`, `mam praci` → `práci`, and rare junk like `maze's` sinks.
- **Valid-but-wrong words**: in Czech sentences, an accentless word that is valid on its own still gets flagged when an accented form fits the sentence far better (`Nemam cas` → `Nemám čas`, `Mam rad` → `Mám rád`). An occasional false flag on a correct rare word is the accepted trade-off. Tune `BilingualSpeller.missingAccentMargin`: lower flags more.
- Shows at most 5 suggestions.
- Only underlines and suggests. It never auto-replaces text.

## Install

Requires Xcode / Swift 6.

```sh
scripts/build.sh      # fetches dictionaries + ~400 MB of corpora (first run only), builds build/CzEnSpell.service
scripts/install.sh    # copies to ~/Library/Services (user-level, no sudo)
scripts/probe.sh      # optional end-to-end check
```

Then **System Settings › Keyboard › Text Input › Edit… › Spelling**: choose **Multiple languages (CzEnSpell)**, and turn off **Correct spelling automatically**.

## Uninstall

`scripts/uninstall.sh`, then set Spelling back to **Automatic by Language**.

## Limitations

- Apps with their own engine (Firefox, MS Office) aren't affected.
- No grammar checking.
- The first check right after install or a crash can come back empty while the service starts (~1 s). The next check works.
- Valid-but-wrong detection covers missing accents only, not other real-word mistakes (`byt`/`být` is judged on accents alone, never on grammar).
- Apps already running when you switched the Spelling setting keep the old checker until restarted.
- Memory: ~100 MB for the service plus ~30 MB for the helper.

## Development

`scripts/fetch-dictionaries.sh && swift test`. Constraints and layout are in [AGENTS.md](AGENTS.md).

## Licenses and attribution

- Code in this repo: [MIT](LICENSE). Third-party parts keep their own licences, listed below. A built `CzEnSpell.service` bundles the GPL Czech dictionary, so anyone redistributing the built bundle must follow the GPL for that file.
- [Hunspell](https://github.com/hunspell/hunspell) 1.7.5, vendored in `Sources/CHunspell`: MPL 1.1 / GPL 2 / LGPL 2.1.
- Dictionaries from [LibreOffice/dictionaries](https://github.com/LibreOffice/dictionaries), fetched at build time: `cs_CZ` GPL, `en_US` SCOWL-based.
- Word frequencies from [hermitdave/FrequencyWords](https://github.com/hermitdave/FrequencyWords) (OpenSubtitles 2018), CC-BY-SA 4.0, fetched at build time.
- Bigram models built at build time from the [Leipzig Corpora Collection](https://wortschatz.uni-leipzig.de/en/download) (`ces-cz_web-public_2019_1M`, `eng-com_web-public_2018_1M`). The download page says CC BY and the usage page says CC BY-NC (personal and scientific use), so commercial use needs their consent. The models are built locally and not committed. D. Goldhahn, T. Eckart, U. Quasthoff: Building Large Monolingual Dictionaries at the Leipzig Corpora Collection, LREC 2012.
