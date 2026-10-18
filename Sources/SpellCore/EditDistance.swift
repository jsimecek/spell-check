import Foundation


enum EditDistance {
    /// Case- and diacritic-insensitive form used for all distance comparisons.
    static func fold(_ s: String) -> [Character] {
        Array(s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil))
    }

    /// Optimal string alignment distance (a swapped pair like "teh" costs 1).
    /// Returns nil as soon as the distance is known to exceed `limit`.
    static func distance(_ a: [Character], _ b: [Character], limit: Int = .max) -> Int? {
        if abs(a.count - b.count) > limit { return nil }
        if a.isEmpty || b.isEmpty { return max(a.count, b.count) }
        let width = b.count + 1
        var previous2 = [Int](repeating: 0, count: width)
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: width)
        for i in 1...a.count {
            current[0] = i
            var rowMin = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    value = min(value, previous2[j - 2] + 1)
                }
                current[j] = value
                rowMin = min(rowMin, value)
            }
            if rowMin > limit { return nil }
            (previous2, previous, current) = (previous, current, previous2)
        }
        let result = previous[b.count]
        return result <= limit ? result : nil
    }
}
