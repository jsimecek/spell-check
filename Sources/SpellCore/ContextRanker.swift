/// Where a misspelled word sits: its sentence language and (corrected) neighbours, lowercased.
public struct WordContext: Equatable, Sendable {
    public var language: Language?
    public var left: String?
    public var right: String?

    public init(language: Language?, left: String?, right: String?) {
        self.language = language
        self.left = left
        self.right = right
    }
}

/// A possible correction and where it came from.
struct Candidate: Hashable, Sendable {
    enum Source: Sendable {
        case native, hunspell, restoration, colloquial, neighbor, capitalization
    }

    let text: String
    let language: Language
    let source: Source
}

/// Noisy-channel style ranking: how well a candidate fits between its neighbours (language model)
/// minus how far it is from what was typed. Accent-only differences are free.
enum ContextRanker {
    static let maxGuesses = 5
    static let editPenalty = 10.0
    /// A colloquial-to-standard rewrite ("kterej" -> "který") counts as half an edit.
    static let colloquialEdit = 0.5
    static let foreignLanguagePenalty = 3.0
    static let nativeBonus = 0.5
    static let unknownLanguageModelScore = -30.0

    static func rank(
        word: String, candidates: [Candidate], context: WordContext?, models: [Language: any LanguageModelScoring]
    ) -> [String] {
        let typed = EditDistance.fold(word)
        let lowered = word.lowercased()
        let typedAllCaps = word == word.uppercased()
        var bestScores: [String: Double] = [:]
        for candidate in candidates
        where candidate.source == .capitalization || isShowable(candidate.text, lowered: lowered, typedAllCaps: typedAllCaps) {
            let candidateScore = score(of: candidate, typed: typed, context: context, models: models)
            bestScores[candidate.text] = max(bestScores[candidate.text] ?? -.infinity, candidateScore)
        }
        // "Muzea" next to "muzea" for a lowercase word is noise; capitalized-only candidates (names) stay.
        if word.first?.isLowercase == true {
            for text in bestScores.keys where text.first?.isUppercase == true && bestScores[text.lowercased()] != nil {
                bestScores[text] = nil
            }
        }
        // Highest score first; ties alphabetically so the order is stable.
        return bestScores.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(maxGuesses)
            .map(\.key)
    }

    private static func score(
        of candidate: Candidate, typed: [Character], context: WordContext?, models: [Language: any LanguageModelScoring]
    ) -> Double {
        let edits =
            candidate.source == .colloquial
            ? colloquialEdit
            : Double(EditDistance.distance(typed, EditDistance.fold(candidate.text)) ?? 0)
        var score =
            models[candidate.language]?.contextScore(
                candidate.text.lowercased(), left: context?.left, right: context?.right
            ) ?? unknownLanguageModelScore
        score -= edits * editPenalty
        if let language = context?.language, language != candidate.language { score -= foreignLanguagePenalty }
        if candidate.source == .native { score += nativeBonus }
        return score
    }

    /// Drops the typed word itself (in any case), acronyms for non-acronyms and lone letters for longer words.
    private static func isShowable(_ candidate: String, lowered: String, typedAllCaps: Bool) -> Bool {
        if candidate.lowercased() == lowered { return false }
        if !typedAllCaps, candidate.count > 1, candidate == candidate.uppercased() { return false }
        return candidate.count > 1 || lowered.count <= 2
    }
}
