import Foundation

/// Lowercased words with UTF-16 ranges and sentence numbers. Shared by the model builder and the
/// runtime so both see identical tokens.
enum NGramTokenizer {
    struct Token: Equatable, Sendable {
        let word: String
        let range: NSRange
        let sentence: Int
    }

    private static let sentenceEnds: Set<Unicode.Scalar> = [".", "!", "?", "\n", "…"]
    private static let apostrophes: Set<Unicode.Scalar> = ["'", "\u{2019}"]

    static func tokens(in text: String) -> [Token] {
        var tokens: [Token] = []
        var sentence = 0
        var word = String.UnicodeScalarView()
        var wordStart = 0
        var offset = 0  // UTF-16 offset of the current scalar
        // An apostrophe is kept only between letters ("don't"), so it waits for the next letter.
        var pendingApostrophe = false

        func finishWord() {
            guard !word.isEmpty else { return }
            let trailingApostrophe = pendingApostrophe ? 1 : 0
            let range = NSRange(location: wordStart, length: offset - wordStart - trailingApostrophe)
            tokens.append(Token(word: String(word).lowercased(), range: range, sentence: sentence))
            word = String.UnicodeScalarView()
            pendingApostrophe = false
        }

        for scalar in text.unicodeScalars {
            if CharacterSet.letters.contains(scalar) || CharacterSet.nonBaseCharacters.contains(scalar) {
                if word.isEmpty { wordStart = offset }
                if pendingApostrophe {
                    word.append("'")
                    pendingApostrophe = false
                }
                word.append(scalar)
            } else if apostrophes.contains(scalar), !word.isEmpty, !pendingApostrophe {
                pendingApostrophe = true
            } else {
                finishWord()
                // Only a sentence with words in it can end, so "?!" or "..." count once.
                if sentenceEnds.contains(scalar), tokens.last?.sentence == sentence { sentence += 1 }
            }
            offset += scalar.utf16.count
        }
        finishWord()
        return tokens
    }
}
