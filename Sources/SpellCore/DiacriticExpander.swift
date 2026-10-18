/// Generates every Czech diacritic spelling of a word typed without (some) accents,
/// e.g. "praci" -> "práci", "prací", ... Callers keep only the ones a dictionary accepts.
public enum DiacriticExpander {
    static let maxVariants = 4096

    private static let lowercaseVariants: [Character: [Character]] = [
        "a": ["á"], "c": ["č"], "d": ["ď"], "e": ["é", "ě"], "i": ["í"], "n": ["ň"], "o": ["ó"],
        "r": ["ř"], "s": ["š"], "t": ["ť"], "u": ["ú", "ů"], "y": ["ý"], "z": ["ž"],
    ]

    private static let allVariants: [Character: [Character]] = lowercaseVariants.reduce(into: [:]) { map, entry in
        map[entry.key] = entry.value
        map[Character(entry.key.uppercased())] = entry.value.map { Character($0.uppercased()) }
    }

    public static func variants(of word: String) -> [String] {
        let options = word.map { [$0] + (allVariants[$0] ?? []) }
        var total = 1
        for choice in options {
            total *= choice.count
            if total > maxVariants { return [] }
        }
        guard total > 1 else { return [] }
        var results: [String] = [""]
        for choice in options {
            results = results.flatMap { prefix in choice.map { prefix + String($0) } }
        }
        return results.filter { $0 != word }
    }
}
