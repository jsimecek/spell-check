import Foundation
import Testing

@testable import SpellCore

/// `CZEN_TUNE=1 CZEN_EVAL=1 swift test -c release -Xswiftc -enable-testing --filter tuneRanking`:
/// generates candidates once, then scores each weight variant on them in seconds.
/// Choose by the tune columns, confirm on holdout; `CZEN_EVAL_ONLY` narrows the sets.
extension BenchmarkTests {
    struct Prepared {
        let word: String
        let candidates: [Candidate]
        let context: WordContext
        let expected: String
    }

    /// Edit while tuning; the first entry is the baseline the others are compared with.
    static func tuningVariants() -> [(String, ContextRanker.Weights)] {
        let base = ContextRanker.Weights()
        var variants = [("current", base)]
        func sweep(_ name: String, _ values: [Double], _ path: WritableKeyPath<ContextRanker.Weights, Double>) {
            for value in values {
                var weights = base
                weights[keyPath: path] = value
                variants.append(("\(name)=\(value)", weights))
            }
        }
        sweep("editPenalty", [10, 12], \.editPenalty)
        sweep("nearbyKey", [0.75, 1], \.errorCosts.nearbyKey)
        return variants
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CZEN_TUNE"] == "1"))
    func tuneRanking() throws {
        let sets = try (guessSets() + corpusGuessSets()).filter { Self.isSelected($0.0) }
        var prepared: [(name: String, halves: [[Prepared]])] = []
        for (name, cases, language) in sets {
            var halves: [[Prepared]] = [[], []]
            for (index, testCase) in cases.enumerated() {
                if let item = prepare(testCase, language: language) { halves[index % 2].append(item) }
            }
            prepared.append((name, halves))
        }
        let models = speller.models.mapValues { $0 as any LanguageModelScoring }
        var baseline: [[Double]] = []
        for (label, weights) in Self.tuningVariants() {
            // Per set: [tune, holdout] top-1 %.
            let scores = prepared.map { set in
                set.halves.map { items in
                    let hits = items.filter {
                        ContextRanker.rank(word: $0.word, candidates: $0.candidates, context: $0.context, models: models, weights: weights)
                            .first == $0.expected
                    }
                    return 100 * Double(hits.count) / Double(max(items.count, 1))
                }
            }
            if baseline.isEmpty { baseline = scores }
            let mean = { (half: Int) in Self.format(scores.map { $0[half] }.reduce(0, +) / Double(max(scores.count, 1))) }
            let deltas = zip(prepared, zip(scores, baseline)).map { set, pair in
                "\(set.name) \(Self.signed(pair.0[0] - pair.1[0]))/\(Self.signed(pair.0[1] - pair.1[1]))"
            }
            print("TUNE \(label): tune=\(mean(0)) holdout=\(mean(1)) | \(deltas.joined(separator: ", "))")
        }
    }

    /// Mirrors `score(_:language:into:)`: a sentence case must be flagged first so its context is remembered.
    private func prepare(_ testCase: Case, language: Language) -> Prepared? {
        var typed = testCase.typed
        var expected = testCase.expected
        let input: (word: String, candidates: [Candidate], context: WordContext)
        if let sentence = testCase.sentence {
            let nsSentence = sentence as NSString
            let range = testCase.range ?? nsSentence.range(of: testCase.typed, options: .caseInsensitive)
            guard range.location != NSNotFound else { return nil }
            typed = nsSentence.substring(with: range)
            if typed.first?.isUppercase == true { expected = expected.uppercasingFirstLetter() }
            guard speller.misspellings(in: sentence).contains(range) else { return nil }
            input = speller.rankingInput(for: typed, context: nil)
        } else {
            guard !speller.isCorrect(typed) else { return nil }
            input = speller.rankingInput(for: typed, context: WordContext(language: language, left: nil, right: nil))
        }
        return Prepared(word: input.word, candidates: input.candidates, context: input.context, expected: expected)
    }

    static func signed(_ value: Double) -> String {
        (value >= 0 ? "+" : "") + format(value)
    }
}
