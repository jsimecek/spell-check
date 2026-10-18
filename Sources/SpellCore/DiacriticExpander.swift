/// Generates every Czech diacritic spelling of a word typed without (some) accents,
/// e.g. "praci" -> "práci", "prací", ... Callers keep only the ones a dictionary accepts.
enum DiacriticExpander {
    /// Words with more spellings than this get none.
    static let maxVariants = 4096

    private static let accentedLowercase: [Character: [Character]] = [
        "a": ["á"], "c": ["č"], "d": ["ď"], "e": ["é", "ě"], "i": ["í"], "n": ["ň"], "o": ["ó"],
        "r": ["ř"], "s": ["š"], "t": ["ť"], "u": ["ú", "ů"], "y": ["ý"], "z": ["ž"],
    ]

    private static let accentedForms: [Character: [Character]] = accentedLowercase.reduce(into: [:]) { forms, entry in
        forms[entry.key] = entry.value
        forms[Character(entry.key.uppercased())] = entry.value.map { Character($0.uppercased()) }
    }

    static func variants(of word: String) -> [String] {
        let choicesPerCharacter = word.map { [$0] + (accentedForms[$0] ?? []) }
        var combinationCount = 1
        for choices in choicesPerCharacter {
            combinationCount *= choices.count
            if combinationCount > maxVariants { return [] }
        }
        guard combinationCount > 1 else { return [] }
        var spellings = [""]
        for choices in choicesPerCharacter {
            spellings = spellings.flatMap { prefix in choices.map { prefix + String($0) } }
        }
        return spellings.filter { $0 != word }
    }
}
