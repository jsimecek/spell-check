import Testing

@testable import SpellCore

/// Scores by a fixed table instead of a real model.
private struct FakeModel: LanguageModelScoring {
    var scores: [String: Double] = [:]
    func contextScore(_ word: String, left: String?, right: String?) -> Double {
        scores["\(left ?? "_") \(word)"] ?? scores[word] ?? -20
    }
}

@Suite struct ContextRankerTests {
    private func rank(
        _ word: String, _ candidates: [(String, Language)], context: WordContext? = nil,
        cs: [String: Double] = [:], en: [String: Double] = [:]
    ) -> [String] {
        ContextRanker.rank(
            word: word,
            candidates: candidates.map { Candidate(text: $0.0, language: $0.1, source: .hunspell) },
            context: context,
            models: [.czech: FakeModel(scores: cs), .english: FakeModel(scores: en)]
        )
    }

    @Test func accentOnlyDifferenceBeatsRealEdits() {
        #expect(rank("protoze", [("provoze", .czech), ("protéze", .czech), ("protože", .czech)]).first == "protože")
    }

    @Test func leftNeighborDecidesBetweenAccentVariants() {
        let cs = ["mám práci": -3.0, "mám prací": -9.0, "s prací": -3.0, "s práci": -9.0]
        let candidates: [(String, Language)] = [("prací", .czech), ("práci", .czech)]
        #expect(rank("praci", candidates, context: WordContext(language: .czech, left: "mám", right: nil), cs: cs).first == "práci")
        #expect(rank("praci", candidates, context: WordContext(language: .czech, left: "s", right: nil), cs: cs).first == "prací")
    }

    @Test func sentenceLanguageBreaksTies() {
        let candidates: [(String, Language)] = [("ten", .czech), ("the", .english)]
        let en = WordContext(language: .english, left: nil, right: nil)
        let cs = WordContext(language: .czech, left: nil, right: nil)
        #expect(rank("teh", candidates, context: en).first == "the")
        #expect(rank("teh", candidates, context: cs).first == "ten")
    }

    @Test func closerCandidateBeatsForeignPenalty() {
        let ranked = rank(
            "recieve", [("recidiva", .czech), ("receive", .english)],
            context: WordContext(language: .czech, left: nil, right: nil))
        #expect(ranked.first == "receive")
    }

    @Test func rareJunkLosesToCommonWord() {
        let en = ["muses": -12.0, "maze's": -19.0]
        #expect(rank("muzes", [("maze's", .english), ("muses", .english)], en: en).first == "muses")
    }

    @Test func removesDuplicatesTheWordItselfAndCapsLength() {
        let many = (0..<30).map { ("word\($0)", Language.english) }
        let ranked = rank("wor", [("wor", .czech), ("word0", .czech)] + many)
        #expect(ranked.count == ContextRanker.maxGuesses)
        #expect(Set(ranked).count == ranked.count)
        #expect(!ranked.contains("wor"))
    }

    @Test func lowercaseWordDropsCapitalizedDuplicates() {
        let ranked = rank("muzes", [("Muzea", .czech), ("muzea", .czech), ("Praha", .czech)])
        #expect(ranked.contains("muzea"))
        #expect(!ranked.contains("Muzea"))
        #expect(ranked.contains("Praha"))
    }

    @Test func dropsTheTypedWordInAnotherCaseAndForeignAcronyms() {
        let ranked = rank("cas", [("čas", .czech), ("Cas", .czech), ("CAS", .english), ("nás", .czech)])
        #expect(ranked == ["čas", "nás"])
        #expect(rank("Nemam", [("Nemám", .czech), ("nemam", .czech)]) == ["Nemám"])
    }

    @Test func keepsCapitalizationFixOfTheTypedWord() {
        let ranked = ContextRanker.rank(
            word: "monday",
            candidates: [
                Candidate(text: "Monday", language: .english, source: .capitalization),
                Candidate(text: "today", language: .english, source: .hunspell),
            ],
            context: nil,
            models: [.english: FakeModel()]
        )
        #expect(ranked == ["Monday", "today"])
    }

    @Test func showsAtMostFiveGuesses() {
        #expect(ContextRanker.maxGuesses == 5)
    }

    @Test func colloquialStandardFormCountsAsNearlyFree() {
        let ranked = ContextRanker.rank(
            word: "kterej",
            candidates: [
                Candidate(text: "terej", language: .czech, source: .hunspell),
                Candidate(text: "který", language: .czech, source: .colloquial),
            ],
            context: nil,
            models: [.czech: FakeModel(scores: ["terej": -15, "který": -8])]
        )
        #expect(ranked.first == "který")
    }
}
