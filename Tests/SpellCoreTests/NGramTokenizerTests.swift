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
