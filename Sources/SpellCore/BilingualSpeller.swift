import Foundation

/// Czech + English spell checking: a word is correct if either dictionary accepts it,
/// so code-mixed text ("pošli mi pull request") is not flagged.
public final class BilingualSpeller {
    private let dictionaries: [Language: HunspellDictionary]
    private let frequencies: [Language: FrequencyList]
    private let models: [Language: NGramModel]
    private let learned: LearnedWords
    private let nativeGuesses: NativeGuessProviding?
    // NSSpellServer asks for guesses without the sentence, so remember where each flagged word came from.
    private var contextByWord: [String: WordContext] = [:]
    // Evicted generation, still consulted so eviction never drops the last check's context.
    private var previousContextByWord: [String: WordContext] = [:]
    private var restorationCache: [String: [String]] = [:]
    private static let maxRememberedContexts = 2000
    private static let maxCachedRestorations = 5000
    /// log-likelihood margin by which an accented form must beat a valid accentless word
    /// ("nemam" -> "nemám") before the word is flagged; lower flags more.
    static let missingAccentMargin = 3.0
    private static let neighborDistance = 2

    public init(dictionaryDirectory: URL, learnedWords: LearnedWords, nativeGuesses: NativeGuessProviding? = nil) throws {
        func required(_ name: String) throws -> URL {
            let url = dictionaryDirectory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { throw SpellCoreError.missingDictionary(url) }
            return url
        }
        var loaded: [Language: HunspellDictionary] = [:]
        var lists: [Language: FrequencyList] = [:]
        var ngrams: [Language: NGramModel] = [:]
        for language in Language.allCases {
            loaded[language] = try HunspellDictionary(directory: dictionaryDirectory, name: language.dictionaryName)
            lists[language] = try FrequencyList(url: required("\(language.rawValue)_50k.txt"))
            ngrams[language] = try NGramModel(url: required("\(language.rawValue).ngram"))
        }
        dictionaries = loaded
        frequencies = lists
        models = ngrams
        learned = learnedWords
        self.nativeGuesses = nativeGuesses
    }

    public func isCorrect(_ word: String) -> Bool {
        isCorrect(word, context: nil)
    }

    /// In Czech text an English-only word that is really Czech typed without accents
    /// ("ted" -> "teď") is flagged; genuine English terms ("review") are not.
    func isCorrect(_ word: String, context: Language?) -> Bool {
        if learned.contains(word) { return true }
        if dictionaries[.czech]?.isCorrect(word) == true { return true }
        let normalized = word.replacingOccurrences(of: "\u{2019}", with: "'")
        guard dictionaries[.english]?.isCorrect(normalized) == true else { return false }
        guard context == .czech else { return true }
        return czechRestorations(of: word).isEmpty
    }

    public func misspellings(in text: String) -> [NSRange] {
        // Evict before the check, so the words it flags keep their context until the next one.
        if contextByWord.count >= Self.maxRememberedContexts {
            previousContextByWord = contextByWord
            contextByWord.removeAll()
        }
        let ns = text as NSString
        let tokens = NGramTokenizer.tokens(in: text)
        let tokenAt = Dictionary(tokens.indices.map { (tokens[$0].range.location, $0) }, uniquingKeysWith: { a, _ in a })
        let languages = sentenceLanguages(tokens, in: ns)
        let fallback = LanguageDetector.detect(text)
        var misspelled: [NSRange] = []
        for range in WordScanner.words(in: text) {
            let word = ns.substring(with: range)
            let index = tokenAt[range.location]
            let language = index.flatMap { languages[tokens[$0].sentence] } ?? fallback
            func context() -> WordContext {
                WordContext(
                    language: language,
                    left: index.flatMap { neighbor(of: $0, step: -1, tokens: tokens, in: ns, language: language) },
                    right: index.flatMap { neighbor(of: $0, step: 1, tokens: tokens, in: ns, language: language) }
                )
            }
            if !isCorrect(word, context: language) {
                misspelled.append(range)
                remember(word, context())
            } else if language == .czech, !learned.contains(word), Self.hasNoDiacritics(word),
                      !czechRestorations(of: word).isEmpty {
                let wordContext = context()
                guard hasLikelierAccentedForm(word, in: wordContext) else { continue }
                misspelled.append(range)
                remember(word, wordContext)
            }
        }
        if !misspelled.isEmpty { nativeGuesses?.prefetch(misspelled.map(ns.substring(with:))) }
        return misspelled
    }

    /// `context` nil means: use what the last check remembered about this word.
    public func guesses(for word: String, context explicit: WordContext? = nil) -> [String] {
        let context = explicit ?? rememberedContext(of: word)
            ?? WordContext(language: LanguageDetector.detect(word), left: nil, right: nil)
        var candidates: [Candidate] = []
        if let native = nativeGuesses?.cachedGuesses(for: word) {
            candidates += native.czech.map { Candidate(text: $0, language: .czech, source: .native) }
            candidates += native.english.map { Candidate(text: $0, language: .english, source: .native) }
        } else {
            nativeGuesses?.prefetch([word])
        }
        for (language, dictionary) in dictionaries {
            candidates += dictionary.suggestions(for: word).filter { Self.isUsefulSuggestion($0, in: language) }
                .map { Candidate(text: $0, language: language, source: .hunspell) }
            candidates += (frequencies[language]?.neighbors(of: word, maxDistance: Self.neighborDistance) ?? [])
                .filter(dictionary.isCorrect)
                .map { Candidate(text: $0, language: language, source: .neighbor) }
        }
        candidates += czechRestorations(of: word).map { Candidate(text: $0, language: .czech, source: .restoration) }
        candidates += ColloquialCzech.standardForms(of: word).filter { dictionaries[.czech]?.isCorrect($0) == true }
            .map { Candidate(text: $0, language: .czech, source: .colloquial) }
        candidates += capitalizationFixes(of: word)
        return ContextRanker.rank(word: word, candidates: candidates, context: context, models: models)
    }

    /// "monday" -> "Monday", "usa" -> "USA": a rejected lowercase word whose capitalized form a dictionary accepts.
    /// Hunspell accepts the all-caps form of any word it knows ("PRAHA" via "Praha"), so all caps is offered
    /// only when "Usa" is rejected, and only without an accent fix, so "cas" gets "čas", not "CAS".
    private func capitalizationFixes(of word: String) -> [Candidate] {
        guard word == word.lowercased(), !isCorrect(word) else { return [] }
        let capitalized = word.prefix(1).uppercased() + word.dropFirst()
        func fixes(_ form: String) -> [Candidate] {
            dictionaries.filter { $0.value.isCorrect(form) }
                .map { Candidate(text: form, language: $0.key, source: .capitalization) }
        }
        let capitalizedFixes = fixes(capitalized)
        guard capitalizedFixes.isEmpty, czechRestorations(of: word).isEmpty else { return capitalizedFixes }
        return fixes(word.uppercased())
    }

    /// Throws when the store cannot be saved; the word still counts as learned until restart.
    public func learn(_ word: String) throws {
        try learned.add(word)
    }

    public func forget(_ word: String) throws {
        try learned.remove(word)
    }

    /// Text views re-check the bare selected word before showing the menu; that must not
    /// overwrite the sentence context remembered from the full check.
    private func remember(_ word: String, _ context: WordContext) {
        if context.left == nil, context.right == nil, rememberedContext(of: word) != nil { return }
        contextByWord[word] = context
    }

    private func rememberedContext(of word: String) -> WordContext? {
        contextByWord[word] ?? previousContextByWord[word]
    }

    private func czechRestorations(of word: String) -> [String] {
        if let cached = restorationCache[word] { return cached }
        guard let czech = dictionaries[.czech] else { return [] }
        let restorations = DiacriticExpander.variants(of: word).filter(czech.isCorrect)
        if restorationCache.count >= Self.maxCachedRestorations { restorationCache.removeAll() }
        restorationCache[word] = restorations
        return restorations
    }

    /// Real-word error check for Czech typed without accents: "Nemam cas" is valid Czech word by word,
    /// but "Nemám" fits the sentence far better.
    private func hasLikelierAccentedForm(_ word: String, in context: WordContext) -> Bool {
        guard let model = models[.czech] else { return false }
        let typed = model.contextScore(word.lowercased(), left: context.left, right: context.right)
        let best = czechRestorations(of: word)
            .map { model.contextScore($0.lowercased(), left: context.left, right: context.right) }
            .max() ?? -.infinity
        return best - typed >= Self.missingAccentMargin
    }

    private static func hasNoDiacritics(_ word: String) -> Bool {
        word.folding(options: .diacriticInsensitive, locale: nil) == word
    }

    /// Neighbouring word for the language model, normalized to its most common Czech accent form
    /// ("rad" -> "rád") so context is judged as if typed with accents; invalid words without one are dropped.
    private func neighbor(
        of index: Int, step: Int, tokens: [NGramTokenizer.Token], in text: NSString, language: Language?
    ) -> String? {
        let other = index + step
        guard tokens.indices.contains(other), tokens[other].sentence == tokens[index].sentence else { return nil }
        let original = text.substring(with: tokens[other].range)
        let valid = dictionaries.values.contains { $0.isCorrect(original) }
        if valid, language != .czech { return tokens[other].word }
        let forms = czechRestorations(of: original).map { $0.lowercased() } + (valid ? [tokens[other].word] : [])
        return forms.max { (models[.czech]?.count($0) ?? 0) < (models[.czech]?.count($1) ?? 0) }
    }

    /// Per-sentence language from the recognizer, overruled by dictionary evidence when it is unsure.
    private func sentenceLanguages(_ tokens: [NGramTokenizer.Token], in text: NSString) -> [Int: Language] {
        var result: [Int: Language] = [:]
        for sentence in Dictionary(grouping: tokens, by: \.sentence).values {
            guard let first = sentence.first, let last = sentence.last else { continue }
            let span = NSRange(location: first.range.location, length: NSMaxRange(last.range) - first.range.location)
            var czechOnly = 0
            var englishOnly = 0
            for token in sentence {
                let original = text.substring(with: token.range)
                let cs = dictionaries[.czech]?.isCorrect(original) == true
                let en = dictionaries[.english]?.isCorrect(original) == true
                if cs && !en || !cs && !en && !czechRestorations(of: original).isEmpty { czechOnly += 1 }
                if en && !cs { englishOnly += 1 }
            }
            let recognized = LanguageDetector.hypothesis(text.substring(with: span))
            if let recognized, recognized.confidence >= LanguageDetector.strongConfidence {
                result[first.sentence] = recognized.language
            } else if czechOnly != englishOnly {
                result[first.sentence] = czechOnly > englishOnly ? .czech : .english
            } else if let recognized, recognized.confidence >= LanguageDetector.minimumConfidence {
                result[first.sentence] = recognized.language
            }
        }
        return result
    }

    /// Hunspell sometimes proposes splits like "nevi m"; single-letter parts are noise unless they are
    /// real words ("v práci", "a lot").
    private static func isUsefulSuggestion(_ suggestion: String, in language: Language) -> Bool {
        let words = oneLetterWords[language] ?? []
        return !suggestion.split(separator: " ").contains { $0.count == 1 && !words.contains($0) }
    }

    private static let oneLetterWords: [Language: Set<Substring>] = [
        .czech: ["a", "i", "k", "o", "s", "u", "v", "z", "A", "I", "K", "O", "S", "U", "V", "Z"],
        .english: ["a", "A", "I"],
    ]
}
