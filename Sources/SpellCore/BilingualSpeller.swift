import Foundation

/// Czech + English spell checking: a word is correct if either dictionary accepts it,
/// so code-mixed text ("pošli mi pull request") is not flagged.
public final class BilingualSpeller {
    /// Log-likelihood margin by which an accented form must beat a valid accentless word
    /// ("nemam" -> "nemám") before the word is flagged; lower flags more.
    static let missingAccentMargin = 3.0
    /// The same for an English word in Czech text ("ted" -> "teď"); English titles ("The Times") stay unflagged.
    static let englishWordAccentMargin = 0.0
    /// Margin when the sentence's other words carry accents: that writer types them, so a bare valid word is likelier meant.
    static let accentedSentenceMargin = 5.0
    /// Log-likelihood ratio at which word frequencies alone decide a sentence's language.
    static let decisiveLanguageEvidence = 1.0
    static let maxWordLanguageEvidence = 6.0
    private static let neighborDistance = 2
    private static let maxRememberedContexts = 2000
    private static let maxCachedRestorations = 5000
    private static let hyphens: Set<unichar> = [0x2D, 0x2010, 0x2011]

    private let dictionaries: [Language: HunspellDictionary]
    private let frequencies: [Language: FrequencyList]
    let models: [Language: NGramModel]
    private let learned: LearnedWords
    private let nativeGuesses: (any NativeGuessProviding)?

    // NSSpellServer asks for guesses without the sentence, so remember where each flagged word came from.
    private var contextByWord: [String: WordContext] = [:]
    // Previous generation, still consulted so eviction never drops the last check's context.
    private var previousContextByWord: [String: WordContext] = [:]
    private var restorationCache: [String: [String]] = [:]

    public init(
        dictionaryDirectory: URL, learnedWords: LearnedWords, nativeGuesses: (any NativeGuessProviding)? = nil
    ) throws {
        func existingFile(_ name: String) throws -> URL {
            let url = dictionaryDirectory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { throw SpellCoreError.missingDictionary(url) }
            return url
        }
        var dictionaries: [Language: HunspellDictionary] = [:]
        var frequencies: [Language: FrequencyList] = [:]
        var models: [Language: NGramModel] = [:]
        for language in Language.allCases {
            dictionaries[language] = try HunspellDictionary(directory: dictionaryDirectory, name: language.dictionaryName)
            frequencies[language] = try FrequencyList(url: existingFile("\(language.rawValue)_50k.txt"))
            models[language] = try NGramModel(url: existingFile("\(language.rawValue).ngram"))
        }
        self.dictionaries = dictionaries
        self.frequencies = frequencies
        self.models = models
        self.learned = learnedWords
        self.nativeGuesses = nativeGuesses
    }

    // MARK: - Checking

    func isCorrect(_ word: String) -> Bool {
        isCorrect(word, in: nil)
    }

    /// In Czech text an English-only word that is really Czech typed without accents
    /// ("ted" -> "teď") is flagged; genuine English terms ("review") are not.
    func isCorrect(_ word: String, in language: Language?) -> Bool {
        if learned.contains(word) { return true }
        if dictionaries[.czech]?.isCorrect(word) == true { return true }
        let normalized = word.replacingOccurrences(of: "\u{2019}", with: "'")
        guard dictionaries[.english]?.isCorrect(normalized) == true else { return false }
        guard language == .czech else { return true }
        return czechRestorations(of: word).isEmpty
    }

    /// Misspelled words, plus valid Czech words whose accented form fits the sentence far better.
    public func misspellings(in text: String) -> [NSRange] {
        // Evict before the check, so the words it flags keep their context until the next one.
        if contextByWord.count >= Self.maxRememberedContexts {
            previousContextByWord = contextByWord
            contextByWord.removeAll()
        }
        let nsText = text as NSString
        let tokens = NGramTokenizer.tokens(in: text)
        let tokenIndexByLocation = Dictionary(
            tokens.indices.map { (tokens[$0].range.location, $0) }, uniquingKeysWith: { first, _ in first }
        )
        let languageBySentence = sentenceLanguages(of: tokens, in: nsText)
        let textLanguage = LanguageDetector.detect(text)
        let isBareWord = tokens.count == 1
        var misspelled: [NSRange] = []
        for range in WordScanner.words(in: text) {
            let word = nsText.substring(with: range).removingSoftHyphens
            let tokenIndex = tokenIndexByLocation[range.location]
            let language = tokenIndex.flatMap { languageBySentence[tokens[$0].sentence] } ?? textLanguage
            // Built on demand: finding the neighbours is the expensive part.
            func context() -> WordContext {
                WordContext(
                    language: language,
                    left: tokenIndex.flatMap { neighbor(of: $0, step: -1, in: tokens, text: nsText, language: language) },
                    right: tokenIndex.flatMap { neighbor(of: $0, step: 1, in: tokens, text: nsText, language: language) }
                )
            }
            if !isCorrect(word, in: language) {
                if isDottedAbbreviation(word, at: range, in: nsText, language: language) { continue }
                if isInCorrectCompound(range, in: nsText, language: language) { continue }
                let wordContext = context()
                if isCorrect(word), !hasLikelierAccentedForm(word, in: wordContext, margin: Self.englishWordAccentMargin) {
                    continue
                }
                misspelled.append(range)
                remember(wordContext, for: word, isBareWord: isBareWord)
            } else if language == .czech, mightBeMissingAccents(word) {
                let wordContext = context()
                let writerTypesAccents = tokenIndex.map { sentenceHasOtherAccents($0, in: tokens) } ?? false
                let margin = writerTypesAccents ? Self.accentedSentenceMargin : Self.missingAccentMargin
                guard hasLikelierAccentedForm(word, in: wordContext, margin: margin) else { continue }
                misspelled.append(range)
                remember(wordContext, for: word, isBareWord: isBareWord)
            }
        }
        if !misspelled.isEmpty { nativeGuesses?.prefetch(misspelled.map { nsText.substring(with: $0).removingSoftHyphens }) }
        return misspelled
    }

    /// "atd.", "Ing.": the Czech dictionary knows these only with the dot, which the word range leaves out.
    /// Czech must reject the bare word, since Hunspell ignores a trailing dot ("ted." is "ted").
    /// In English sentences only capitalized ones count ("Ing. Novák"), so an English typo like "mal." is not hidden.
    private func isDottedAbbreviation(_ word: String, at range: NSRange, in text: NSString, language: Language?) -> Bool {
        guard language != .english || word.first?.isUppercase == true,
            NSMaxRange(range) < text.length, text.character(at: NSMaxRange(range)) == 0x2E,
            let czech = dictionaries[.czech]
        else { return false }
        return !czech.isCorrect(word) && czech.isCorrect(word + ".")
    }

    /// "Wi-Fi", "česko-německý": the parts are checked alone, but the dictionaries know the whole compound.
    private func isInCorrectCompound(_ range: NSRange, in text: NSString, language: Language?) -> Bool {
        guard let compound = Self.hyphenatedCompound(around: range, in: text) else { return false }
        let word = text.substring(with: compound).removingSoftHyphens
            .replacingOccurrences(of: "\u{2010}", with: "-")
            .replacingOccurrences(of: "\u{2011}", with: "-")
        return isCorrect(word, in: language)
    }

    /// The hyphen-joined run of letters around `range`, or nil when no hyphen joins it to a neighbour.
    private static func hyphenatedCompound(around range: NSRange, in text: NSString) -> NSRange? {
        func isLetter(_ index: Int) -> Bool {
            guard index >= 0, index < text.length, let scalar = Unicode.Scalar(text.character(at: index)) else {
                return false
            }
            return CharacterSet.letters.contains(scalar)
        }
        func isHyphen(_ index: Int) -> Bool {
            index >= 0 && index < text.length && hyphens.contains(text.character(at: index))
        }
        // Soft hyphens sit inside the parts ("če\u{AD}sko-ně\u{AD}mecký"), never join them.
        func isPartOfWord(_ index: Int) -> Bool {
            isLetter(index) || (index >= 0 && index < text.length && text.character(at: index) == 0xAD)
        }
        // Composing NFD text to NFC shrinks it to at most 1.5 UTF-16 units per byte, so a longer run exceeds
        // Hunspell's limit; the cap keeps long hyphen chains from costing a full walk per flagged part.
        let limit = 2 * HunspellDictionary.maxWordBytes
        var start = range.location
        var end = NSMaxRange(range)
        while isHyphen(start - 1), isLetter(start - 2), end - start <= limit {
            start -= 1
            while isPartOfWord(start - 1), end - start <= limit { start -= 1 }
        }
        while isHyphen(end), isLetter(end + 1), end - start <= limit {
            end += 1
            while isPartOfWord(end), end - start <= limit { end += 1 }
        }
        if end - start > limit { return nil }
        let compound = NSRange(location: start, length: end - start)
        return compound == range ? nil : compound
    }

    // MARK: - Guesses

    /// `context` nil means: use what the last check remembered about this word.
    public func guesses(for word: String, context explicitContext: WordContext? = nil) -> [String] {
        let input = rankingInput(for: word, context: explicitContext)
        return ContextRanker.rank(word: input.word, candidates: input.candidates, context: input.context, models: models)
    }

    /// Everything `ContextRanker` needs; the benchmark reuses it to tune weights without regenerating candidates.
    func rankingInput(for word: String, context explicitContext: WordContext?) -> (
        word: String, candidates: [Candidate], context: WordContext
    ) {
        let word = word.removingSoftHyphens
        let context =
            explicitContext ?? rememberedContext(of: word)
            ?? WordContext(language: language(ofSentence: word), left: nil, right: nil)
        return (word, candidates(for: word, language: context.language), context)
    }

    private func candidates(for word: String, language sentenceLanguage: Language?) -> [Candidate] {
        var candidates = nativeCandidates(for: word)
        for (language, dictionary) in dictionaries {
            // Czech suggestions take most of the time and rarely win in an English sentence.
            if !(language == .czech && sentenceLanguage == .english) {
                candidates += dictionary.suggestions(for: word)
                    .filter { Self.isUsefulSuggestion($0, in: language) }
                    .map { Candidate(text: $0, language: language, source: .hunspell) }
            }
            candidates += (frequencies[language]?.neighbors(of: word, maxDistance: Self.neighborDistance) ?? [])
                .filter(dictionary.isCorrect)
                .map { Candidate(text: $0, language: language, source: .neighbor) }
        }
        candidates += czechRestorations(of: word).map { Candidate(text: $0, language: .czech, source: .restoration) }
        candidates += ColloquialCzech.standardForms(of: word)
            .filter { dictionaries[.czech]?.isCorrect($0) == true }
            .map { Candidate(text: $0, language: .czech, source: .colloquial) }
        candidates += capitalizationFixes(of: word)
        return candidates
    }

    /// Apple's guesses if the helper has already answered; otherwise asks for them for next time.
    private func nativeCandidates(for word: String) -> [Candidate] {
        guard let nativeGuesses else { return [] }
        guard let guesses = nativeGuesses.cachedGuesses(for: word) else {
            nativeGuesses.prefetch([word])
            return []
        }
        return guesses.czech.map { Candidate(text: $0, language: .czech, source: .native) }
            + guesses.english.map { Candidate(text: $0, language: .english, source: .native) }
    }

    /// "monday" -> "Monday", "usa" -> "USA": a rejected lowercase word whose capitalized form a dictionary accepts.
    /// Hunspell accepts the all-caps form of any word it knows ("PRAHA" via "Praha"), so all caps is offered
    /// only when "Usa" is rejected, and only without an accent fix, so "cas" gets "čas", not "CAS".
    private func capitalizationFixes(of word: String) -> [Candidate] {
        guard word == word.lowercased(), !isCorrect(word) else { return [] }
        let capitalizedFixes = capitalizationCandidates(word.uppercasingFirstLetter())
        guard capitalizedFixes.isEmpty, czechRestorations(of: word).isEmpty else { return capitalizedFixes }
        return capitalizationCandidates(word.uppercased())
    }

    private func capitalizationCandidates(_ form: String) -> [Candidate] {
        dictionaries.filter { $0.value.isCorrect(form) }
            .map { Candidate(text: form, language: $0.key, source: .capitalization) }
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

    // MARK: - Learning

    /// Throws when the store cannot be saved; the word still counts as learned until restart.
    public func learn(_ word: String) throws {
        try learned.add(word)
    }

    public func forget(_ word: String) throws {
        try learned.remove(word)
    }

    // MARK: - Sentence context

    /// Text views re-check the bare selected word before showing the menu; that must not
    /// overwrite the sentence context remembered from the full check.
    private func remember(_ context: WordContext, for word: String, isBareWord: Bool) {
        if isBareWord, rememberedContext(of: word) != nil { return }
        contextByWord[word] = context
    }

    private func rememberedContext(of word: String) -> WordContext? {
        contextByWord[word] ?? previousContextByWord[word]
    }

    /// Neighbouring word for the language model, normalized to its most common Czech accent form
    /// ("rad" -> "rád") so context is judged as if typed with accents; invalid words without one are dropped.
    private func neighbor(
        of index: Int, step: Int, in tokens: [NGramTokenizer.Token], text: NSString, language: Language?
    ) -> String? {
        let neighborIndex = index + step
        guard tokens.indices.contains(neighborIndex), tokens[neighborIndex].sentence == tokens[index].sentence else {
            return nil
        }
        let token = tokens[neighborIndex]
        let original = text.substring(with: token.range).removingSoftHyphens
        let isValid = dictionaries.values.contains { $0.isCorrect(original) }
        if isValid, language != .czech { return token.word }
        let forms = czechRestorations(of: original).map { $0.lowercased() } + (isValid ? [token.word] : [])
        return forms.max { czechCount(of: $0) < czechCount(of: $1) }
    }

    private func czechCount(of word: String) -> UInt32 {
        models[.czech]?.count(word) ?? 0
    }

    /// Language of each sentence, keyed by sentence number.
    private func sentenceLanguages(of tokens: [NGramTokenizer.Token], in text: NSString) -> [Int: Language] {
        var languages: [Int: Language] = [:]
        for (sentence, sentenceTokens) in Dictionary(grouping: tokens, by: \.sentence) {
            languages[sentence] = language(ofSentence: sentenceTokens, in: text)
        }
        return languages
    }

    func language(ofSentence sentence: String) -> Language? {
        language(ofSentence: NGramTokenizer.tokens(in: sentence), in: sentence as NSString)
    }

    /// Word-frequency evidence first; Apple's recognizer only when the words do not decide.
    private func language(ofSentence tokens: [NGramTokenizer.Token], in text: NSString) -> Language? {
        guard let first = tokens.first, let last = tokens.last else { return nil }
        let ratio = czechLikelihoodRatio(of: tokens, in: text)
        if abs(ratio) >= Self.decisiveLanguageEvidence { return ratio > 0 ? .czech : .english }
        let span = NSRange(location: first.range.location, length: NSMaxRange(last.range) - first.range.location)
        guard let recognized = LanguageDetector.hypothesis(text.substring(with: span)),
            recognized.confidence >= LanguageDetector.minimumConfidence
        else { return nil }
        return recognized.language
    }

    /// log P(words | Czech) - log P(words | English) from the unigram counts; positive means Czech.
    /// A word English rejects counts as its commonest Czech accented form ("prijdu" as "přijdu"), and
    /// each word's say is capped so one English term ("pull request") cannot outvote a Czech sentence.
    private func czechLikelihoodRatio(of tokens: [NGramTokenizer.Token], in text: NSString) -> Double {
        guard let czech = models[.czech], let english = models[.english] else { return 0 }
        let czechTotal = log(Double(max(czech.totalTokens, 1)))
        let englishTotal = log(Double(max(english.totalTokens, 1)))
        return tokens.reduce(0) { ratio, token in
            let original = text.substring(with: token.range).removingSoftHyphens
            // Restoring English words would cost thousands of Hunspell lookups each on every check.
            let isEnglish = dictionaries[.english]?.isCorrect(original.replacingOccurrences(of: "\u{2019}", with: "'")) == true
            let restorations = isEnglish ? [] : czechRestorations(of: original)
            let forms = [token.word] + restorations.map { $0.lowercased() }
            let czechCount = forms.map(czechCount(of:)).max() ?? 0
            let englishCount = english.count(token.word)
            // A word neither corpus knows would only favour the smaller corpus through the smoothing.
            guard czechCount > 0 || englishCount > 0 else { return ratio }
            let czechLog = log(Double(czechCount) + 0.5) - czechTotal
            let englishLog = log(Double(englishCount) + 0.5) - englishTotal
            return ratio + min(max(czechLog - englishLog, -Self.maxWordLanguageEvidence), Self.maxWordLanguageEvidence)
        }
    }

    // MARK: - Missing accents

    /// Czech spellings of `word` with accents restored ("praci" -> "práci", "prací").
    private func czechRestorations(of word: String) -> [String] {
        if let cached = restorationCache[word] { return cached }
        // Accents only add bytes, so a word Hunspell rejects for length has no restorations; skips 4096 long variants.
        guard let czech = dictionaries[.czech],
            word.precomposedStringWithCanonicalMapping.utf8.count <= HunspellDictionary.maxWordBytes
        else { return [] }
        let restorations = DiacriticExpander.variants(of: word).filter(czech.isCorrect)
        if restorationCache.count >= Self.maxCachedRestorations { restorationCache.removeAll() }
        restorationCache[word] = restorations
        return restorations
    }

    private func sentenceHasOtherAccents(_ index: Int, in tokens: [NGramTokenizer.Token]) -> Bool {
        let sentence = tokens[index].sentence
        return tokens.indices.contains { $0 != index && tokens[$0].sentence == sentence && tokens[$0].word.hasDiacritics }
    }

    /// A correct word that could also be Czech typed without accents ("mam" for "mám").
    private func mightBeMissingAccents(_ word: String) -> Bool {
        !learned.contains(word) && !word.hasDiacritics && !czechRestorations(of: word).isEmpty
    }

    /// Real-word error check for Czech typed without accents: "Nemam cas" is valid Czech word by word,
    /// but "Nemám" fits the sentence far better.
    private func hasLikelierAccentedForm(_ word: String, in context: WordContext, margin: Double) -> Bool {
        guard let model = models[.czech] else { return false }
        let typedScore = model.contextScore(word.lowercased(), left: context.left, right: context.right)
        let bestAccentedScore =
            czechRestorations(of: word)
            .map { model.contextScore($0.lowercased(), left: context.left, right: context.right) }
            .max() ?? -.infinity
        return bestAccentedScore - typedScore >= margin
    }
}
