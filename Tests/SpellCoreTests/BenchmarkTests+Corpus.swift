import Foundation
import Testing

@testable import SpellCore

/// Benchmarks on held-out Leipzig news sentences (scripts/fetch-benchmark.sh): errors injected into
/// real text, false positives on correct text and language detection on sentences and short snippets.
extension BenchmarkTests {
    static let corpora: [Language: String] = [.czech: "ces_news_2022_30K", .english: "eng_news_2023_30K"]
    static let guessSentences = 400
    static let checkSentences = 1500
    static let languageSentences = 1000
    /// Valid words flagged for missing accents in correct Czech news text (measured: 5 in ~23k words).
    static let maxCorpusAccentFlags = 8
    static let corpusLanguageFloor = 98.0

    @Test func corpusGuesses() throws {
        try run(corpusGuessSets())
    }

    func corpusGuessSets() throws -> [(String, [Case], Language)] {
        let czech = try Self.corpusSentences(.czech, count: Self.guessSentences)
        let english = try Self.corpusSentences(.english, count: Self.guessSentences)
        var random = SplitMix(seed: 7)
        let sets: [(String, [Case], Language)] = [
            ("cs-ctx-strip", czech.compactMap { injected(into: $0, &random, pick: \.hasDiacritics) { word, _ in SyntheticCzech.strip(word) } }, .czech),
            ("cs-ctx-strip-sentence", czech.compactMap { strippedSentence($0, &random) }, .czech),
            ("cs-ctx-typo", czech.compactMap { injected(into: $0, &random) { SyntheticCzech.typo($0, &$1) } }, .czech),
            ("cs-ctx-i/y", czech.compactMap { injected(into: $0, &random) { word, _ in SyntheticCzech.swapIY(word)?.0 ?? word } }, .czech),
            ("en-ctx-typo", english.compactMap {
                injected(into: $0, &random) { SyntheticCzech.typo($0, &$1, rows: SyntheticCzech.qwertyRows) }
            }, .english),
            ("cs-typo-rare", try rareWordTypos(.czech, &random), .czech),
            ("en-typo-rare", try rareWordTypos(.english, &random), .english),
        ]
        return sets
    }

    @Test func corpusFalsePositives() throws {
        for language in [Language.czech, .english] {
            var tokens = 0
            var accent: [String] = []
            var unknown: [String] = []
            for sentence in try Self.corpusSentences(language, count: Self.checkSentences) {
                tokens += NGramTokenizer.tokens(in: sentence).count
                for range in speller.misspellings(in: sentence) {
                    let word = (sentence as NSString).substring(with: range)
                    if speller.isCorrect(word) { accent.append(word) } else { unknown.append(word) }
                }
            }
            let perThousand = { (count: Int) in Self.format(1000 * Double(count) / Double(max(tokens, 1))) }
            print(
                "BENCH corpus flags \(language.rawValue): tokens=\(tokens) accent=\(accent.count) (\(perThousand(accent.count))/1k) "
                    + "unknown=\(unknown.count) (\(perThousand(unknown.count))/1k)"
            )
            #expect(accent.count <= Self.maxCorpusAccentFlags, "\(language.rawValue) accent flags on correct text")
            if ProcessInfo.processInfo.environment["CZEN_EVAL_VERBOSE"] == "1" {
                print("  FLAG accent \(language.rawValue): \(accent)")
                print("  FLAG unknown \(language.rawValue): \(unknown)")
            }
        }
    }

    @Test func corpusLanguage() throws {
        var random = SplitMix(seed: 11)
        // kind -> [tune, holdout] (correct, total)
        var results: [String: [(Int, Int)]] = [:]
        var misses: [String] = []
        for language in [Language.czech, .english] {
            for (index, sentence) in try Self.corpusSentences(language, count: Self.languageSentences).enumerated() {
                var samples = [("sentence", sentence)]
                if language == .czech { samples.append(("stripped", SyntheticCzech.strip(sentence))) }
                for length in [2, 3] {
                    if let snippet = Self.snippet(of: sentence, words: length, &random) { samples.append(("snippet\(length)", snippet)) }
                }
                for (kind, text) in samples {
                    let detected = speller.language(ofSentence: text)
                    var halves = results[kind] ?? [(0, 0), (0, 0)]
                    halves[index % 2].1 += 1
                    if detected == language { halves[index % 2].0 += 1 } else { misses.append("\(kind) \(text) -> \(detected?.rawValue ?? "nil")") }
                    results[kind] = halves
                }
            }
        }
        for kind in results.keys.sorted() {
            for (half, result) in zip(["tune", "holdout"], results[kind]!) {
                print("BENCH corpus language \(kind) \(half): \(result.0)/\(result.1) (\(Self.format(100 * Double(result.0) / Double(max(result.1, 1))))%)")
            }
            let holdout = results[kind]![1]
            #expect(100 * Double(holdout.0) / Double(max(holdout.1, 1)) >= Self.corpusLanguageFloor, "\(kind) language holdout")
        }
        if ProcessInfo.processInfo.environment["CZEN_EVAL_VERBOSE"] == "1" {
            for miss in misses.prefix(200) { print("  MISS corpus language: \(miss)") }
        }
    }

    // MARK: - Data

    /// Evenly spaced sentences of everyday length; the file is sorted, so spacing spreads topics.
    static func corpusSentences(_ language: Language, count: Int) throws -> [String] {
        let url = fetched.appendingPathComponent("\(corpora[language]!)-sentences.txt")
        let sentences = try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline)
            .map { line in line.firstIndex(of: "\t").map { String(line[line.index(after: $0)...]) } ?? String(line) }
            .filter { (40...200).contains(($0 as NSString).length) }
        let step = max(1, sentences.count / count)
        return stride(from: 0, to: sentences.count, by: step).prefix(count).map { sentences[$0] }
    }

    /// Lowercase words past the first, at least 4 letters, that the speller accepts in this sentence.
    private func correctWords(in sentence: String) -> [NGramTokenizer.Token] {
        let nsSentence = sentence as NSString
        let tokens = NGramTokenizer.tokens(in: sentence)
        let flagged = Set(speller.misspellings(in: sentence).map(\.location))
        return tokens.dropFirst().filter { token in
            let original = nsSentence.substring(with: token.range)
            return original == token.word && token.word.count >= 4 && !flagged.contains(token.range.location)
        }
    }

    /// One random correct word replaced by `corrupt(word)`; nil when nothing changes or the result is a valid word
    /// (real-word errors other than missing accents are out of scope).
    private func injected(
        into sentence: String, _ random: inout SplitMix, pick: (String) -> Bool = { _ in true },
        _ corrupt: (String, inout SplitMix) -> String
    ) -> Case? {
        let words = correctWords(in: sentence).filter { pick($0.word) }
        guard !words.isEmpty else { return nil }
        let token = words[random.next(words.count)]
        let typed = corrupt(token.word, &random)
        guard typed != token.word, typed.allSatisfy(\.isLetter) else { return nil }
        // Missing accents are in scope even when the bare form is a word ("prace").
        if speller.isCorrect(typed), SyntheticCzech.strip(token.word) != typed { return nil }
        let text = (sentence as NSString).replacingCharacters(in: token.range, with: typed)
        let range = NSRange(location: token.range.location, length: (typed as NSString).length)
        return Case(typed: typed, expected: token.word, sentence: text, range: range)
    }

    /// The whole sentence typed without accents; the target is one word that had them.
    private func strippedSentence(_ sentence: String, _ random: inout SplitMix) -> Case? {
        let words = correctWords(in: sentence).filter(\.word.hasDiacritics)
        guard !words.isEmpty else { return nil }
        let token = words[random.next(words.count)]
        let stripped = SyntheticCzech.strip(sentence)
        let strippedTokens = NGramTokenizer.tokens(in: stripped)
        guard let index = NGramTokenizer.tokens(in: sentence).firstIndex(of: token), strippedTokens.indices.contains(index)
        else { return nil }
        let range = strippedTokens[index].range
        return Case(typed: (stripped as NSString).substring(with: range), expected: token.word, sentence: stripped, range: range)
    }

    /// Typos in correct corpus words missing from the 50k frequency list, so recall cannot lean on that list.
    private func rareWordTypos(_ language: Language, _ random: inout SplitMix) throws -> [Case] {
        let common = Set(
            try String(contentsOf: BilingualSpellerTests.dictionaries.appendingPathComponent("\(language.rawValue)_50k.txt"), encoding: .utf8)
                .split(whereSeparator: \.isNewline).map { String($0.split(separator: " ")[0]) }
        )
        var seen: Set<String> = []
        var words: [String] = []
        for sentence in try Self.corpusSentences(language, count: 3000) {
            for token in NGramTokenizer.tokens(in: sentence).dropFirst() where token.word.count >= 5 && !common.contains(token.word) {
                guard seen.insert(token.word).inserted, (sentence as NSString).substring(with: token.range) == token.word,
                    speller.isCorrect(token.word, in: language)
                else { continue }
                words.append(token.word)
            }
        }
        let step = max(1, words.count / 400)
        let rows = language == .czech ? SyntheticCzech.qwertzRows : SyntheticCzech.qwertyRows
        return stride(from: 0, to: words.count, by: step).compactMap { index in
            let word = words[index]
            let typed = SyntheticCzech.typo(word, &random, rows: rows)
            return typed == word ? nil : Case(typed: typed, expected: word, sentence: nil)
        }
    }

    /// `words` consecutive words of the sentence as typed, starting at a random word.
    static func snippet(of sentence: String, words: Int, _ random: inout SplitMix) -> String? {
        let tokens = NGramTokenizer.tokens(in: sentence)
        guard tokens.count > words else { return nil }
        let start = random.next(tokens.count - words + 1)
        let first = tokens[start].range
        let last = tokens[start + words - 1].range
        return (sentence as NSString).substring(with: NSRange(location: first.location, length: NSMaxRange(last) - first.location))
    }
}
