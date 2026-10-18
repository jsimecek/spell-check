import Foundation

/// Typo distance between words, ignoring case and diacritics.
enum EditDistance {
    /// Case- and diacritic-insensitive form used for all distance comparisons.
    static func fold(_ word: String) -> [Character] {
        Array(word.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil))
    }

    /// Optimal string alignment distance (a swapped pair like "teh" costs 1).
    /// Returns nil as soon as the distance is known to exceed `limit`.
    static func distance(_ a: [Character], _ b: [Character], limit: Int = .max) -> Int? {
        if abs(a.count - b.count) > limit { return nil }
        if a.isEmpty || b.isEmpty { return max(a.count, b.count) }
        // Three rolling rows of the DP table: the transposition needs the one two rows back.
        var twoRowsBack = [Int](repeating: 0, count: b.count + 1)
        var previousRow = Array(0...b.count)
        var currentRow = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            currentRow[0] = i
            var rowMinimum = i
            for j in 1...b.count {
                let substitutionCost = a[i - 1] == b[j - 1] ? 0 : 1
                var value = min(previousRow[j] + 1, currentRow[j - 1] + 1, previousRow[j - 1] + substitutionCost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    value = min(value, twoRowsBack[j - 2] + 1)
                }
                currentRow[j] = value
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum > limit { return nil }
            (twoRowsBack, previousRow, currentRow) = (previousRow, currentRow, twoRowsBack)
        }
        let result = previousRow[b.count]
        return result <= limit ? result : nil
    }
}
