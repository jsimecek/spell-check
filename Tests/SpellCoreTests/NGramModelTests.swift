import Foundation
import Testing
@testable import SpellCore

@Suite struct NGramTokenizerTests {
    @Test func lowercasesSplitsSentencesAndKeepsApostrophes() {
        let tokens = NGramTokenizer.tokens(in: "Mám práci. Don’t stop, OK?")
        #expect(tokens.map(\.word) == ["mám", "práci", "don't", "stop", "ok"])
        #expect(tokens.map(\.sentence) == [0, 0, 1, 1, 1])
    }

    @Test func reportsUTF16Ranges() {
        let text = "🐴 kůň běží"
        let tokens = NGramTokenizer.tokens(in: text)
        #expect(tokens.map { (text as NSString).substring(with: $0.range) } == ["kůň", "běží"])
    }
}

@Suite struct NGramModelTests {
    static let corpus = [
        "1\tMám práci a mám práci rád.",
        "2\tJsem spokojený s prací.",
        "3\tMám práci.",
        "4\tProsím tě, můžeš mi to poslat?",
        "5\tProsím tě o to.",
    ]

    static func model(minCount: UInt32 = 1) throws -> NGramModel {
        try NGramModel(data: NGramModel.build(lines: corpus, minCount: minCount))
    }

    @Test func hashIsStableAcrossRuns() {
        // FNV-1a 64; models built earlier must stay readable.
        #expect(NGramModel.hash("a") == 0xaf63dc4c8601ec8c)
    }

    @Test func countsUnigramsAndBigrams() throws {
        let m = try Self.model()
        #expect(m.count("práci") == 3)
        #expect(m.count("mám", "práci") == 3)
        #expect(m.count("s", "prací") == 1)
        #expect(m.count("práci", "jsem") == 0)  // no pairs across sentences
        #expect(m.count("neexistuje") == 0)
    }

    @Test func minCountDropsRareEntries() throws {
        let m = try Self.model(minCount: 2)
        #expect(m.count("mám", "práci") == 3)
        #expect(m.count("s", "prací") == 0)
    }

    @Test func contextPrefersWordSeenAfterLeftNeighbor() throws {
        let m = try Self.model()
        #expect(m.contextScore("práci", left: "mám", right: nil) > m.contextScore("prací", left: "mám", right: nil))
        #expect(m.contextScore("prací", left: "s", right: nil) > m.contextScore("práci", left: "s", right: nil))
        #expect(m.contextScore("tě", left: "prosím", right: nil) > m.contextScore("té", left: "prosím", right: nil))
    }

    @Test func canSkipSentencesTypedWithoutAccents() throws {
        let lines = ["1\tMam rad kafe a caj.", "2\tMám rád kafe.", "3\tAno."]
        let m = try NGramModel(data: NGramModel.build(lines: lines, minCount: 1, skipUnaccentedSentences: true))
        #expect(m.count("mam") == 0)
        #expect(m.count("mám", "rád") == 1)
        #expect(m.count("ano") == 1)  // too short to judge, kept
    }

    @Test func rejectsCorruptData() {
        #expect(throws: (any Error).self) { try NGramModel(data: Data("nope".utf8)) }
    }
}
