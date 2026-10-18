import Foundation

/// Finds the words worth spell checking and skips code-like tokens, URLs, emails and acronyms.
public enum WordScanner {
    private static let whitespaceDelimitedToken = try! NSRegularExpression(pattern: #"\S+"#)
    private static let technicalMarker = try! NSRegularExpression(pattern: ##"@|://|[/\\#]|\p{L}\.\p{L}|^www\."##)

    public static func words(in text: String) -> [NSRange] {
        let nsText = text as NSString
        let technicalRanges = technicalTokenRanges(in: nsText)
        var nextTechnical = 0
        var words: [NSRange] = []
        nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length), options: .byWords) { word, range, _, _ in
            // Words and technical tokens both come in text order, so one forward sweep finds any overlap.
            while nextTechnical < technicalRanges.count, NSMaxRange(technicalRanges[nextTechnical]) <= range.location {
                nextTechnical += 1
            }
            let isInTechnicalToken =
                nextTechnical < technicalRanges.count
                && NSIntersectionRange(technicalRanges[nextTechnical], range).length > 0
            guard let word, shouldCheck(word), !isInTechnicalToken else { return }
            words.append(range)
        }
        return words
    }

    /// Skips words with fewer than two letters, digits or "_", all caps (acronyms) and camelCase.
    private static func shouldCheck(_ word: String) -> Bool {
        let letterCount = word.unicodeScalars.filter(CharacterSet.letters.contains).count
        guard letterCount >= 2 else { return false }
        if word.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) || $0 == "_" }) { return false }
        if word == word.uppercased() { return false }
        return !isCamelCase(word)
    }

    private static func isCamelCase(_ word: String) -> Bool {
        zip(word, word.dropFirst()).contains { $0.isLowercase && $1.isUppercase }
    }

    /// Whitespace-delimited tokens that look like URLs, emails, paths or domains, in text order.
    private static func technicalTokenRanges(in text: NSString) -> [NSRange] {
        whitespaceDelimitedToken.matches(in: text as String, range: NSRange(location: 0, length: text.length))
            .map(\.range)
            .filter { range in
                let token = text.substring(with: range) as NSString
                return technicalMarker.firstMatch(in: token as String, range: NSRange(location: 0, length: token.length)) != nil
            }
    }
}
