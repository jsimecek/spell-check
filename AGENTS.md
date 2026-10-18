# CzEnSpell

macOS spell-checking service (NSSpellServer) for Czech + English. Swift package, macOS 14+.

## Commands
- `scripts/fetch-dictionaries.sh`: download pinned dictionaries and frequency lists into `Dictionaries/`. Required before `swift test`.
- `swift test`: unit tests plus integration tests against the real dictionaries.
- `scripts/build.sh` → `build/CzEnSpell.service`; `scripts/install.sh` / `scripts/uninstall.sh` (user-level only, `~/Library/Services`).
- `scripts/probe.sh [mul|auto|cs|en]`: runs `scripts/probe-sentences.txt` through `NSSpellChecker` like a real app.

## Layout
- `Sources/SpellCore`: all logic (tokenizing, cs/en detection, Hunspell wrapper, guess ranking). Keep it testable without AppKit.
- `Sources/CzEnSpellServer`: thin NSSpellServer bridge + process bootstrap.
- `Sources/CHunspell`: vendored Hunspell 1.7.5, unmodified (see `VENDORED.md`). Do not edit.
- `Sources/spellprobe`: end-to-end probe CLI.
- `Sources/ngram-build`: builds `Dictionaries/{cs,en}.ngram` from Leipzig sentences (run by `scripts/fetch-dictionaries.sh`).

## Hard-won constraints (verified on macOS 27.0.1)
- Bundle must be `CFBundlePackageType` `APPL` and run an `NSApplication` loop, or LaunchServices launch fails with `errAETimeout`. `BNDL` is listed but never launched.
- Delegate callbacks arrive on the main thread, one at a time. Never call `NSSpellChecker` from the server: it stalls ~1 s, then returns nothing.
- Apple's guesses come from the helper (`CzEnSpell --apple-helper`, same binary, pipe + JSON lines). Its `NSSpellChecker` pings every spell server, ours included, so a request made while the server is inside a callback stalls ~0.5 s. Hence `NativeGuessClient` never waits: words are prefetched when flagged and read from the cache. Argument-domain overrides of the spelling defaults do not avoid the ping (tested).
- `NSSpellChecker` only discovers third-party servers inside a running `NSApplication` (plain CLI scripts do not see them).
- Language id is `mul`, shown in the Spelling menu as "Multiple languages (CzEnSpell)". Apple's own services do not use `mul`.
- `NSSpellServer` guess callbacks get only the word, so `BilingualSpeller` remembers each flagged word's sentence context. A re-check of the bare word (text views do that before the menu) must not overwrite it.
- The unified check returns `.spelling` results plus one `.orthography` result (claims `mul`, so right-click guesses come back to us). Never `.correction`, so nothing gets auto-replaced.
- Never log user text (only counts and timings).
- Third-party data (GPL cs_CZ dictionary, CC-BY-SA frequency lists) is fetched with pinned commits + sha256, never committed.
