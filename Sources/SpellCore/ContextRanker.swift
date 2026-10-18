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

public struct Candidate: Hashable, Sendable {
    public enum Source: Sendable { case native, hunspell, restoration, colloquial, neighbor, capitalization }

    public let text: String
    public let language: Language
    public let source: Source
}

/// Noisy-channel style ranking: how well a candidate fits between its neighbours (language model)
/// minus how far it is from what was typed. Accent-only differences are free.
public enum ContextRanker {
    public static let maxGuesses = 5
    static let editPenalty = 10.0
    static let colloquialEdit = 0.5
    static let foreignLanguagePenalty = 3.0
    static let nativeBonus = 0.5
    static let unknownLanguageModelScore = -30.0

    public static func rank(
        word: String, candidates: [Candidate], context: WordContext?, models: [Language: LanguageModelScoring]
    ) -> [String] {
        let folded = EditDistance.fold(word)
        var best: [String: Double] = [:]
        let lowered = word.lowercased()
        let typedAllCaps = word == word.uppercased()
        for candidate in candidates
        where candidate.source == .capitalization || isShowable(candidate.text, lowered: lowered, typedAllCaps: typedAllCaps) {
            let edits = candidate.source == .colloquial
                ? colloquialEdit
                : Double(EditDistance.distance(folded, EditDistance.fold(candidate.text)) ?? 0)
            var score = models[candidate.language]?.contextScore(
                candidate.text.lowercased(), left: context?.left, right: context?.right
            ) ?? unknownLanguageModelScore
            score -= edits * editPenalty
            if let language = context?.language, language != candidate.language { score -= foreignLanguagePenalty }
            if candidate.source == .native { score += nativeBonus }
            best[candidate.text] = max(best[candidate.text] ?? -.infinity, score)
        }
        // "Muzea" next to "muzea" for a lowercase word is noise; capitalized-only candidates (names) stay.
        if word.first?.isLowercase == true {
            for candidate in best.keys where candidate.first?.isUppercase == true && best[candidate.lowercased()] != nil {
                best[candidate] = nil
            }
        }
        return best.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(maxGuesses)
            .map(\.key)
    }

    /// Drops the typed word itself (in any case), acronyms for non-acronyms and lone letters for longer words.
    private static func isShowable(_ candidate: String, lowered: String, typedAllCaps: Bool) -> Bool {
        if candidate.lowercased() == lowered { return false }
        if !typedAllCaps, candidate.count > 1, candidate == candidate.uppercased() { return false }
        return candidate.count > 1 || lowered.count <= 2
    }
}
