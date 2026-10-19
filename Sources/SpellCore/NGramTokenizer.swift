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
    private static let softHyphen: Unicode.Scalar = "\u{AD}"

    static func tokens(in text: String) -> [Token] {
        var tokens: [Token] = []
        var sentence = 0
        var word = String.UnicodeScalarView()
        var wordStart = 0
        var offset = 0  // UTF-16 offset of the current scalar
        // An apostrophe is kept only between letters ("don't"), so it waits for the next letter.
        var pendingApostrophe = false
        // UTF-16 length after the last letter that only a following letter would make part of the range.
        var pendingLength = 0

        func finishWord() {
            guard !word.isEmpty else { return }
            let range = NSRange(location: wordStart, length: offset - wordStart - pendingLength)
            tokens.append(Token(word: String(word).lowercased(), range: range, sentence: sentence))
            word = String.UnicodeScalarView()
            pendingApostrophe = false
            pendingLength = 0
        }

        for scalar in text.unicodeScalars {
            if CharacterSet.letters.contains(scalar) || CharacterSet.nonBaseCharacters.contains(scalar) {
                if word.isEmpty { wordStart = offset }
                if pendingApostrophe {
                    word.append("'")
                    pendingApostrophe = false
                }
                pendingLength = 0
                word.append(scalar)
            } else if apostrophes.contains(scalar), !word.isEmpty, !pendingApostrophe {
                pendingApostrophe = true
                pendingLength += scalar.utf16.count
            } else if scalar == softHyphen, !word.isEmpty {
                // Invisible break hint ("pra\u{AD}ci"): inside the range, left out of the word.
                pendingLength += scalar.utf16.count
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
