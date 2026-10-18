import Foundation

/// Finds the words worth spell checking and skips code-like tokens, URLs, emails and acronyms.
public enum WordScanner {
    public static func words(in text: String) -> [NSRange] {
        let ns = text as NSString
        let technical = technicalTokenRanges(in: ns)
        var result: [NSRange] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byWords) { word, range, _, _ in
            guard let word, shouldCheck(word),
                  !technical.contains(where: { NSIntersectionRange($0, range).length > 0 }) else { return }
            result.append(range)
        }
        return result
    }

    static func shouldCheck(_ word: String) -> Bool {
        let letters = word.unicodeScalars.filter(CharacterSet.letters.contains)
        guard letters.count >= 2 else { return false }
        if word.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) || $0 == "_" }) { return false }
        if word == word.uppercased() { return false }
        return !isCamelCase(word)
    }

    private static func isCamelCase(_ word: String) -> Bool {
        let chars = Array(word)
        return zip(chars, chars.dropFirst()).contains { $0.isLowercase && $1.isUppercase }
    }

    private static let technicalPattern = try! NSRegularExpression(
        pattern: ##"@|://|[/\\#]|\p{L}\.\p{L}|^www\."##
    )

    /// Whitespace-delimited tokens that look like URLs, emails, paths or domains.
    private static func technicalTokenRanges(in text: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        let scanner = try! NSRegularExpression(pattern: #"\S+"#)
        for match in scanner.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
            let token = text.substring(with: match.range)
            let tokenRange = NSRange(location: 0, length: (token as NSString).length)
            if technicalPattern.firstMatch(in: token, range: tokenRange) != nil {
                ranges.append(match.range)
            }
        }
        return ranges
    }
}
