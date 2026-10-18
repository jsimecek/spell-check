import Foundation

/// Lowercased words with UTF-16 ranges and sentence numbers. Shared by the model builder and the
/// runtime so both see identical tokens.
public enum NGramTokenizer {
    public struct Token: Equatable, Sendable {
        public let word: String
        public let range: NSRange
        public let sentence: Int
    }

    private static let sentenceEnd: Set<Unicode.Scalar> = [".", "!", "?", "\n", "…"]
    private static let apostrophes: Set<Unicode.Scalar> = ["'", "\u{2019}"]

    public static func tokens(in text: String) -> [Token] {
        var tokens: [Token] = []
        var sentence = 0
        var current = String.UnicodeScalarView()
        var start = 0
        var offset = 0
        var pendingApostrophe = false

        func flush() {
            guard !current.isEmpty else { return }
            tokens.append(Token(word: String(current).lowercased(),
                                range: NSRange(location: start, length: offset - start - (pendingApostrophe ? 1 : 0)),
                                sentence: sentence))
            current = String.UnicodeScalarView()
            pendingApostrophe = false
        }

        for scalar in text.unicodeScalars {
            let width = scalar.utf16.count
            if CharacterSet.letters.contains(scalar) || CharacterSet.nonBaseCharacters.contains(scalar) {
                if current.isEmpty { start = offset }
                if pendingApostrophe { current.append("'"); pendingApostrophe = false }
                current.append(scalar)
            } else if apostrophes.contains(scalar), !current.isEmpty, !pendingApostrophe {
                pendingApostrophe = true
            } else {
                flush()
                if sentenceEnd.contains(scalar), tokens.last?.sentence == sentence { sentence += 1 }
            }
            offset += width
        }
        flush()
        return tokens
    }
}
