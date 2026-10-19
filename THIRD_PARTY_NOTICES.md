# Third-party notices

CzEnSpell's own code is under the [MIT License](LICENSE). The components below keep their own licenses. Only Hunspell is in this repository; the data files are downloaded by `scripts/fetch-dictionaries.sh` (pinned to a commit or checksum) and copied into the built `CzEnSpell.service` by `scripts/build.sh`.

This is a summary, not legal advice. The upstream license texts are authoritative.

## Hunspell 1.7.5

- Where: `Sources/CHunspell`, unmodified source from <https://github.com/hunspell/hunspell> tag `v1.7.5` (see `Sources/CHunspell/VENDORED.md`). Compiled into the `CzEnSpell` executable.
- License: tri-licensed MPL 1.1, GPL 2.0 or later, or LGPL 2.1 or later, at your choice (`Sources/CHunspell/license.hunspell`, `COPYING`, `COPYING.LESSER`, `COPYING.MPL`). Parts derived from MySpell carry a BSD-style notice (`Sources/CHunspell/license.myspell`).

## Czech Hunspell dictionary (cs_CZ)

- Where: `cs_CZ/cs_CZ.aff` and `cs_CZ/cs_CZ.dic` from <https://github.com/LibreOffice/dictionaries> at commit `67032ee957631908098a72edf48dc81cac27e369`. In the bundle as data files, not compiled into the program.
- Authors: based on the Czech ispell dictionary by Petr Kolář and contributors; 2021 update by Miroslav Pošta.
- License: GNU GPL, per `cs_CZ/README_en.txt` ("This dictionary is licensed under the GNU/GPL license"). `cs_CZ/README_cs.txt` includes the GPL version 2 text; no "or later" clause is stated.

## English Hunspell dictionary (en_US)

- Where: `en/en_US.aff` and `en/en_US.dic` from the same LibreOffice/dictionaries commit. In the bundle as data files.
- Origin: generated from SCOWL by Kevin Atkinson (<http://wordlist.sourceforge.net>, as listed in `en/README_en_US.txt`); the affix file derives from Geoff Kuenning's Ispell. Later edits by Marco A.G. Pinto (per the `.aff` header).
- License: the SCOWL copyright and permission notices in `en/README_en_US.txt` (permissive, notices must be kept), which include an Ispell BSD-style license and notices for further sources. The same folder also contains `license.txt` (GPL 2) and an older `README.txt` that mentions LGPL; the folder does not say which files those apply to.

## Word frequency lists (FrequencyWords)

- Where: `content/2018/cs/cs_50k.txt` and `content/2018/en/en_50k.txt` from <https://github.com/hermitdave/FrequencyWords> at commit `525f9b560de45753a5ea01069454e72e9aa541c6`, by Hermit Dave, generated from OpenSubtitles 2018 (<http://opus.nlpl.eu/OpenSubtitles2018.php>). In the bundle unmodified.
- License: CC BY-SA 4.0 for the content (the repository's README: "MIT License for code. CC-by-sa-4.0 for content.").

## Leipzig Corpora Collection

- Where: `ces-cz_web-public_2019_1M` and `eng-com_web-public_2018_1M` from <https://downloads.wortschatz-leipzig.de/corpora/> (sha256-pinned). The corpora are not in the bundle. `ngram-build` turns their sentences into `cs.ngram` and `en.ngram`: hashed word and word-pair counts, no text. Those two files are in the bundle.
- License: the Leipzig Terms of Usage (<https://wortschatz.uni-leipzig.de/en/usage>) say the downloadable corpora are under CC BY, and also that the data is free for private and scientific use under CC BY-NC, with commercial use needing written consent. Ask the project before any commercial use. These terms were read from search-engine copies of that page, because the page itself is behind a bot check.
- Citation: D. Goldhahn, T. Eckart, U. Quasthoff: Building Large Monolingual Dictionaries at the Leipzig Corpora Collection: From 100 to 200 Languages. Proceedings of LREC 2012.

## Benchmark data (test only, never in the bundle)

`scripts/fetch-benchmark.sh` downloads these into `Benchmarks/` (sha256-pinned, gitignored) for the opt-in benchmark in `Tests/SpellCoreTests/BenchmarkTests.swift`. They are not in this repository and not in the built bundle.

- Wikipedia, "Lists of common misspellings/For machines", revision `1199637275` (<https://en.wikipedia.org/w/index.php?oldid=1199637275>). License: CC BY-SA 4.0, per Wikipedia's terms; authors are listed in the page history.
- Leipzig Corpora Collection news sentences `ces_news_2022_30K` and `eng_news_2023_30K` (<https://downloads.wortschatz-leipzig.de/corpora/>), terms as in the Leipzig section above. Only the `*-sentences.txt` files are kept.
- `aspell.dat` from Roger Mitton's corpora of misspellings at Birkbeck, University of London (<https://www.dcs.bbk.ac.uk/~ROGER/corpora.html>), derived from Kevin Atkinson's GNU Aspell test list. The page states no license; it is used here only as local test input.

## Note for forks

`build/CzEnSpell.service` contains the MIT-licensed code, compiled Hunspell and the data files above, but none of their license texts. If you share a built bundle, you take on the obligations of every component in it (for example the GPL text and source offer for the Czech dictionary, the SCOWL notices, CC BY-SA and CC BY attribution, and the Leipzig non-commercial clause).
