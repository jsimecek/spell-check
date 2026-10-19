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

    @Test func softHyphenStaysInsideTheToken() {
        let text = "s pra\u{AD}ci\u{AD} \u{AD}a"
        let tokens = NGramTokenizer.tokens(in: text)
        #expect(tokens.map(\.word) == ["s", "praci", "a"])
        #expect(tokens.map { (text as NSString).substring(with: $0.range) } == ["s", "pra\u{AD}ci", "a"])
    }

    @Test(arguments: [
        ("dogs' bowl", ["dogs", "bowl"], [NSRange(location: 0, length: 4), NSRange(location: 6, length: 4)]),
        ("dogs\u{2019} bowl", ["dogs", "bowl"], [NSRange(location: 0, length: 4), NSRange(location: 6, length: 4)]),
        ("dogs'\u{AD} bowl", ["dogs", "bowl"], [NSRange(location: 0, length: 4), NSRange(location: 7, length: 4)]),
        ("don\u{AD}'t", ["don't"], [NSRange(location: 0, length: 6)]),
        ("it'\u{AD}s", ["it's"], [NSRange(location: 0, length: 5)]),
    ])
    func apostropheEndsTheRangeUnlessALetterFollows(text: String, words: [String], ranges: [NSRange]) {
        let tokens = NGramTokenizer.tokens(in: text)
        #expect(tokens.map(\.word) == words)
        #expect(tokens.map(\.range) == ranges)
    }
}
