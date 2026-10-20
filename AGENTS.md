## CzEnSpell

macOS NSSpellServer spell checker for Czech + English. Swift 6, macOS 14+.

### Commands

- `scripts/fetch-dictionaries.sh`: required once before `swift test` (network, ~400 MB). Builds `Dictionaries/`.
- `swift build`, `swift test`: unit + integration tests against real dictionaries.
- Benchmark: `scripts/fetch-benchmark.sh`, then `CZEN_EVAL=1 swift test -c release -Xswiftc -enable-testing --filter BenchmarkTests`. Tune on `tune` rows, judge on `holdout`. `CZEN_EVAL_VERBOSE=1` lists misses, `CZEN_EVAL_ONLY=en-aspell,cs-ctx` filters by prefix.
- Weight tuning: `CZEN_TUNE=1 CZEN_EVAL=1 swift test -c release -Xswiftc -enable-testing --filter tuneRanking` scores `ContextRanker.Weights` variants from `BenchmarkTests+Tuning.swift`.
- `scripts/build.sh` -> `build/CzEnSpell.service`; `scripts/install.sh` / `uninstall.sh` (user-level `~/Library/Services`); `scripts/probe.sh [mul|auto|cs|en]` runs `scripts/probe-sentences.txt` through `NSSpellChecker`.

### Layout

- `Sources/SpellCore`: all logic, AppKit-free. Public only what other targets use; everything else internal, tests use `@testable import`. Entry point `BilingualSpeller` (also decides sentence language: n-gram frequencies first, `LanguageDetector` as tie-breaker). `NGramTokenizer` is shared by `ngram-build` and runtime; keep them consistent.
- `Sources/CzEnSpellServer`: thin NSSpellServer bridge, bootstrap, Apple helper.
- `Sources/CHunspell`: vendored Hunspell 1.7.5. Never edit.
- `Sources/spellprobe`: probe CLI. `Sources/ngram-build`: builds `Dictionaries/{cs,en}.ngram`.
- Bundle ID `io.github.jsimecek.CzEnSpell` (`Resources/Info.plist`) is also the `Logger` subsystem; keep in sync.

### macOS constraints (verified on macOS 27.0.1)

- Bundle must be `CFBundlePackageType` `APPL` running an `NSApplication` loop, else launch fails with `errAETimeout`.
- Delegate callbacks: main thread, serial. Never call `NSSpellChecker` from the server (stalls ~1 s, returns nothing).
- Apple guesses come from the helper (`CzEnSpell --apple-helper`, pipe + JSON lines). Its `NSSpellChecker` pings our server too, so a request during a callback stalls ~0.5 s. `NativeGuessClient` therefore never waits: prefetch on flag, read from cache. Argument-domain default overrides do not avoid the ping.
- `NSSpellChecker` sees third-party servers only inside a running `NSApplication`, not plain CLI scripts.
- Language id `mul` ("Multiple languages (CzEnSpell)").
- Guess callbacks get only the word, so `BilingualSpeller` stores each flagged word's sentence context. A bare-word re-check must not overwrite it.
- Unified check returns `.spelling` results + one `.orthography` (claims `mul`, routes right-click guesses back). Never `.correction` (no auto-replace).
- First probe after install returns empty while the server starts; discard it.
- Third-party data is fetched with pinned commits + sha256, never committed. Changing n-gram output: bump `MODEL_REV` in `scripts/fetch-dictionaries.sh`. Changing a source: update `THIRD_PARTY_NOTICES.md`.

### Rules

- Never log user text: counts, timings, error domains/codes only.
- Comments only when code can't say it, one line usually. No em dashes.
- Shell scripts: `set -euo pipefail`, `shellcheck` clean.

### Verifying a change

1. `swift test`.
2. End-to-end (GUI session): `scripts/build.sh`, `scripts/install.sh`, `scripts/probe.sh mul` once to warm up, then again; diff against a pre-change run (ignore `[N ms]`).
3. Ranking/detection/candidate changes: benchmark before and after, compare holdout rows.
