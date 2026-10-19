# CzEnSpell

macOS spell-checking service (NSSpellServer) for Czech + English. Swift package, Swift 6 language mode, macOS 14+ deployment target. User docs: `README.md`; licensing: `THIRD_PARTY_NOTICES.md`.

## Commands
- `scripts/fetch-dictionaries.sh`: download pinned dictionaries and frequency lists and build the n-gram models into `Dictionaries/`. Required before `swift test`. Network, ~400 MB of corpora on first run.
- `swift build`, `swift test`: unit tests plus integration tests against the real dictionaries.
- `scripts/fetch-benchmark.sh`, then `CZEN_EVAL=1 swift test -c release -Xswiftc -enable-testing --filter BenchmarkTests`: opt-in quality benchmark (guess top-1/top-5, sentence language, false positives, timings). Tune on the `tune` rows, judge on `holdout`; `CZEN_EVAL_VERBOSE=1` lists misses, `CZEN_EVAL_ONLY=en-aspell,cs-ctx` limits guess sets by prefix. The `cs-ctx-*`/`en-ctx-*` rows inject errors into unseen Leipzig news sentences; `corpus flags` counts flags on that correct text.
- `CZEN_TUNE=1 CZEN_EVAL=1 swift test -c release -Xswiftc -enable-testing --filter tuneRanking`: builds candidates once, then scores the `ContextRanker.Weights` variants listed in `BenchmarkTests+Tuning.swift` in seconds.
- `scripts/build.sh` → `build/CzEnSpell.service` (ad-hoc signed); `scripts/install.sh` / `scripts/uninstall.sh` (user-level only, `~/Library/Services`).
- `scripts/probe.sh [mul|auto|cs|en]`: runs `scripts/probe-sentences.txt` through `NSSpellChecker` like a real app.

## Layout
- `Sources/SpellCore`: all logic. Keep it AppKit-free and testable. Public API is only what the other targets use: `BilingualSpeller`, `LearnedWords`, `NativeGuessClient` and its request/response types (plus `NativeGuessProviding` and `NativeGuesses`, which public signatures need), `WordScanner`, `NGramModel` (for `ngram-build`), `WordContext`, `Language`, error enums. Everything else is internal; tests use `@testable import`.
  - `BilingualSpeller`: entry point (check, guesses, learn/forget).
  - `HunspellDictionary`, `FrequencyList`, `NGramModel` + `NGramTokenizer`: data access. `NGramTokenizer` is shared by the model builder and the runtime.
  - `LanguageDetector`, `DiacriticExpander`, `ColloquialCzech`, `EditDistance`, `ErrorModel`, `ContextRanker`: detection, candidates, ranking. Sentence language is decided in `BilingualSpeller` (n-gram word frequencies first, `LanguageDetector` as tie-breaker).
  - `WordScanner`: which words to check (skips URLs, emails, code-like tokens, acronyms).
  - `NativeGuessClient`: pipe to the Apple helper process. `LearnedWords`: user dictionary.
  - `String+Letters.swift`: small shared string helpers (first-letter case, `hasDiacritics`, `removingSoftHyphens`).
- `Sources/CzEnSpellServer`: thin NSSpellServer bridge (`SpellServerDelegate`), process bootstrap (`main.swift`), Apple helper (`AppleHelper`).
- `Sources/CHunspell`: vendored Hunspell 1.7.5, unmodified (see `VENDORED.md`). Do not edit.
- `Sources/spellprobe`: end-to-end probe CLI. `Sources/ngram-build`: builds `Dictionaries/{cs,en}.ngram` from Leipzig sentences.
- `Resources/Info.plist`: bundle plist. Bundle ID `io.github.jsimecek.CzEnSpell`, also the `Logger` subsystem in `Sources/CzEnSpellServer`; keep them in sync.

## Hard-won constraints (verified on macOS 27.0.1)
- Bundle must be `CFBundlePackageType` `APPL` and run an `NSApplication` loop, or LaunchServices launch fails with `errAETimeout`. `BNDL` is listed but never launched.
- Delegate callbacks arrive on the main thread, one at a time. Never call `NSSpellChecker` from the server: it stalls ~1 s, then returns nothing.
- Apple's guesses come from the helper (`CzEnSpell --apple-helper`, same binary, pipe + JSON lines). Its `NSSpellChecker` pings every spell server, ours included, so a request made while the server is inside a callback stalls ~0.5 s. Hence `NativeGuessClient` never waits: words are prefetched when flagged and read from the cache. Argument-domain overrides of the spelling defaults do not avoid the ping (tested).
- `NSSpellChecker` only discovers third-party servers inside a running `NSApplication` (plain CLI scripts do not see them).
- Language id is `mul`, shown in the Spelling menu as "Multiple languages (CzEnSpell)". Apple's own services do not use `mul`.
- `NSSpellServer` guess callbacks get only the word, so `BilingualSpeller` remembers each flagged word's sentence context. A re-check of the bare word (text views do that before the menu) must not overwrite it.
- The unified check returns `.spelling` results plus one `.orthography` result (claims `mul`, so right-click guesses come back to us). Never `.correction`, so nothing gets auto-replaced.
- The first probe after `scripts/install.sh` comes back empty while the server starts; discard it.
- Third-party data (GPL cs_CZ dictionary, CC BY-SA frequency lists, Leipzig corpora) is fetched with pinned commits + sha256, never committed. When changing what ends up in `Dictionaries/`, bump `MODEL_REV` in `scripts/fetch-dictionaries.sh` if the n-gram output changes, and update `THIRD_PARTY_NOTICES.md` if a source changes.

## Code style
- Never log user text. Logs carry counts, timings and error domains/codes only.
- Comments only where the code cannot say it; usually one line. No em dashes in code, comments or docs.
- Don't edit `Sources/CHunspell`. Keep `SpellCore` free of AppKit.
- Keep the SpellCore public surface minimal; prefer `internal` + `@testable` in tests.
- Shell scripts: `set -euo pipefail`; `shellcheck` clean if you have it.

## Verifying a change
1. `swift test` (needs `Dictionaries/`).
2. Local end-to-end, on a Mac with a GUI session: `scripts/build.sh`, `scripts/install.sh`, wait a few seconds, `scripts/probe.sh mul` once as warm-up, then `scripts/probe.sh mul` again and compare its output with a run from before the change (ignore the `[N ms]` timings).
3. When ranking, detection or candidates change: run the benchmark before and after and compare the holdout rows.
4. Optional: `shellcheck scripts/*.sh` if scripts changed.
