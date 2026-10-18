import Foundation
import Testing

@testable import SpellCore

@Suite struct WordScannerTests {
    private func checkedWords(_ text: String) -> [String] {
        WordScanner.words(in: text).map { (text as NSString).substring(with: $0) }
    }

    @Test func returnsUTF16RangesForWordsWithDiacritics() {
        let text = "Žluťoučký 🐴 kůň"
        let ranges = WordScanner.words(in: text)
        #expect(ranges.map { (text as NSString).substring(with: $0) } == ["Žluťoučký", "kůň"])
        #expect(ranges.last == NSRange(location: 13, length: 3))
    }

    @Test func skipsTechnicalTokens() {
        let text = "mail jan@example.com https://dxheroes.io/blog v2 API getUserName snake_case 42 x"
        #expect(checkedWords(text) == ["mail"])
    }

    @Test func keepsApostrophesAndCapitalizedWords() {
        #expect(checkedWords("Don't forget Praha") == ["Don't", "forget", "Praha"])
    }

    @Test func skipsTechnicalTokensBetweenWords() {
        #expect(checkedWords("see a/b and c@d.cz or x.y then done") == ["see", "and", "or", "then", "done"])
    }

    @Test func manyTechnicalTokensScaleLinearly() {
        // A pasted log or file listing must not stall the spell server. Linear takes ~0.15 s in a debug
        // build and quadratic took ~30 s, so the generous limit still catches a regression on slow runners.
        let text = String(repeating: "word a/b ", count: 20_000)
        let start = Date()
        #expect(WordScanner.words(in: text).count == 20_000)
        #expect(Date().timeIntervalSince(start) < 10)
    }
}
