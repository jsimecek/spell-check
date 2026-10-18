import Foundation

/// Common words for near-miss candidates; "word count" lines (hermitdave/FrequencyWords format).
final class FrequencyList {
    private struct Entry {
        let word: String
        let folded: [Character]
    }

    private var seen: Set<String> = []
    private var entriesByLength: [Int: [Entry]] = [:]

    init(url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        var counts: [(String, Double)] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ")
            guard parts.count == 2, let count = Double(parts[1]), count > 1 else { continue }
            counts.append((parts[0].lowercased(), count))
        }
        for (word, _) in counts where seen.insert(word).inserted {
            let folded = EditDistance.fold(word)
            entriesByLength[folded.count, default: []].append(Entry(word: word, folded: folded))
        }
    }

    /// Frequent words within `maxDistance` edits of `word`, ignoring case and diacritics.
    func neighbors(of word: String, maxDistance: Int) -> [String] {
        let folded = EditDistance.fold(word)
        let lowered = word.lowercased()
        let capitalize = word.first?.isUppercase == true
        var result: [String] = []
        for length in max(1, folded.count - maxDistance)...(folded.count + maxDistance) {
            for entry in entriesByLength[length] ?? [] where entry.word != lowered {
                guard EditDistance.distance(folded, entry.folded, limit: maxDistance) != nil else { continue }
                result.append(capitalize ? entry.word.prefix(1).uppercased() + entry.word.dropFirst() : entry.word)
            }
        }
        return result
    }
}
