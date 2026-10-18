import Foundation
import Testing
@testable import SpellCore

/// Integration tests against the real dictionaries from scripts/fetch-dictionaries.sh.
@Suite(.serialized) struct BilingualSpellerTests {
    static let dictionaries = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Dictionaries")

    static let czech = WordContext(language: .czech, left: nil, right: nil)
    static let english = WordContext(language: .english, left: nil, right: nil)

    let speller: BilingualSpeller
    let learnedFile: URL

    init() throws {
        learnedFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("czen-learned-\(UUID().uuidString).txt")
        speller = try BilingualSpeller(
            dictionaryDirectory: Self.dictionaries,
            learnedWords: LearnedWords(storeURL: learnedFile, readOnlySources: [])
        )
    }

    private func flagged(_ text: String) -> [String] {
        speller.misspellings(in: text).map { (text as NSString).substring(with: $0) }
    }

    @Test func flagsCzechWithoutDiacritics() {
        let words = flagged("Dneska nevim jestli zitra prijdu, protoze mam praci.")
        for word in ["nevim", "zitra", "prijdu", "protoze"] {
            #expect(words.contains(word), "\(word) should be flagged")
        }
    }

    @Test func acceptsCorrectCzech() {
        #expect(flagged("Příliš žluťoučký kůň úpěl ďábelské ódy.").isEmpty)
        #expect(flagged("Zítra půjdeme do kina s kamarády, protože máme volno.").isEmpty)
    }

    @Test func acceptsCorrectEnglishAndMixedText() {
        #expect(flagged("I will receive the mail tomorrow.").isEmpty)
        #expect(flagged("Pošli mi ten pull request a já udělám review.").isEmpty)
    }

    @Test func flagsUndiacritizedCzechThatIsAlsoEnglishInCzechContext() {
        #expect(flagged("To je dobrý nápad, ted to vim a není to problem.") == ["ted", "vim", "problem"])
        #expect(flagged("I met Ted at the mall, no problem.").isEmpty)
    }

    @Test func flagsValidWordsWhoseAccentedFormFitsFarBetter() {
        let words = flagged("Nemam cas, zavolam ti zitra.")
        #expect(words.contains("Nemam"))
        #expect(words.contains("cas"))
        #expect(flagged("Posli mi to na email.").contains("Posli"))
        #expect(flagged("Mam rad kafe.").contains("Mam"))
        #expect(flagged("To je dobrý nápad, který jsi mel.").contains("mel"))
    }

    @Test(arguments: [
        "Koupili jsme nový byt v Praze.", "Dal jsem mu knihu.", "To je pro tebe.", "Pak se uvidí.",
        "Jdu na poštu.", "Mám rád kafe a čaj.", "Můžeš mi to poslat zítra?", "Byl jsem tam se sestrou.",
    ])
    func doesNotFlagCorrectCzechWithAccentlessWords(_ sentence: String) {
        #expect(flagged(sentence).isEmpty)
    }

    @Test func accentedFormIsTheTopGuessForValidButWrongWord() {
        _ = speller.misspellings(in: "Nemam cas, zavolam ti zitra.")
        #expect(speller.guesses(for: "Nemam").first == "Nemám")
    }

    @Test func flagsEnglishTypos() {
        #expect(flagged("I definately recieve teh mail tomorow.") == ["definately", "recieve", "teh", "tomorow"])
    }

    @Test(arguments: [
        ("nevim", "nevím"), ("zitra", "zítra"), ("prijdu", "přijdu"),
        ("protoze", "protože"), ("pujdeme", "půjdeme"), ("prosim", "prosím"),
    ])
    func topCzechGuessRestoresDiacritics(_ word: String, _ expected: String) {
        #expect(speller.guesses(for: word, context: Self.czech).first == expected)
    }

    @Test(arguments: [("definately", "definitely"), ("recieve", "receive"), ("tomorow", "tomorrow")])
    func topEnglishGuess(_ word: String, _ expected: String) {
        #expect(speller.guesses(for: word, context: Self.english).first == expected)
    }

    @Test func guessesUseContextRememberedFromLastCheck() {
        _ = speller.misspellings(in: "Dneska nevim jestli zitra prijdu, protoze mam praci.")
        #expect(speller.guesses(for: "praci").first == "práci")
    }

    @Test func sentenceContextPicksTheLikelyWord() {
        _ = speller.misspellings(in: "Ahoj, prosim te muzes mi to poslat?")
        #expect(speller.guesses(for: "prosim").first == "prosím")
        #expect(speller.guesses(for: "te").first == "tě")
        #expect(speller.guesses(for: "muzes").first == "můžeš")
    }

    @Test func leftNeighbourDecidesBetweenAccentVariants() {
        _ = speller.misspellings(in: "Jsem spokojeny s praci.")
        #expect(speller.guesses(for: "praci").first == "prací")
        _ = speller.misspellings(in: "Dneska mam hodne prace a zitra mam taky praci.")
        #expect(speller.guesses(for: "praci").first == "práci")
    }

    @Test func recheckOfTheBareWordKeepsSentenceContext() {
        _ = speller.misspellings(in: "Jsem spokojeny s praci.")
        _ = speller.misspellings(in: "praci")  // text views re-check the selected word before showing the menu
        #expect(speller.guesses(for: "praci").first == "prací")
    }

    @Test func contextEvictionNeverDropsWordsFromTheSameCheck() {
        let letters = "bfghjklmnpqrstvwxz".map(String.init)
        let junk = letters.flatMap { a in letters.flatMap { b in letters.map { c in "qxj" + a + b + c } } }.prefix(2000)
        #expect(flagged(junk.joined(separator: " ")).count == 2000)
        _ = speller.misspellings(in: "Jsem spokojen s praci, nevim.")
        #expect(speller.guesses(for: "praci").first == "prací")
    }

    @Test func accentRestorationBeatsRealEditFavouredByContext() {
        _ = speller.misspellings(in: "Dneska nevim jestli zitra prijdu.")
        #expect(speller.guesses(for: "prijdu").first == "přijdu")
    }

    @Test func accentOnlyFixBeatsCommonerWordOneEditAway() {
        _ = speller.misspellings(in: "Rano jsem musel vstat brzy.")
        #expect(speller.guesses(for: "vstat").first == "vstát")
    }

    @Test func noSingleLetterGuessesForLongerWords() {
        _ = speller.misspellings(in: "I definately recieve teh mail tomorow.")
        #expect(!speller.guesses(for: "teh").contains { $0.count == 1 })
    }

    @Test func englishSentenceGetsEnglishGuesses() {
        _ = speller.misspellings(in: "I definately recieve teh mail tomorow.")
        #expect(speller.guesses(for: "definately").first == "definitely")
        #expect(speller.guesses(for: "recieve").first == "receive")
        #expect(speller.guesses(for: "teh").first == "the")
        #expect(speller.guesses(for: "tomorow").first == "tomorrow")
    }

    @Test func colloquialCzechGetsStandardForms() {
        _ = speller.misspellings(in: "To je dobrej napad, kterej jsi mel.")
        #expect(speller.guesses(for: "dobrej").first == "dobrý")
        #expect(speller.guesses(for: "napad").first == "nápad")
        #expect(speller.guesses(for: "kterej").first == "který")
    }

    @Test func rareJunkIsNotOnTop() {
        _ = speller.misspellings(in: "Ahoj, muzes mi to poslat?")
        let guesses = speller.guesses(for: "muzes")
        #expect(!guesses.prefix(3).contains { $0.contains("'") })
    }

    @Test func frequentWordsWinTiesAndColloquialFormsGetStandardGuesses() {
        #expect(speller.guesses(for: "praci", context: Self.czech).first == "práci")
        #expect(speller.guesses(for: "kterej", context: Self.czech).prefix(3).contains("který"))
        #expect(speller.guesses(for: "teh", context: Self.english).first == "the")
    }

    @Test func dropsSplitGuessesWithSingleLetterParts() {
        #expect(!speller.guesses(for: "nevim", context: Self.czech).contains { $0.contains(" ") })
    }

    @Test func learnedWordIsAcceptedAndForgettable() throws {
        #expect(flagged("Ahoj Bflmpsvz") == ["Bflmpsvz"])
        try speller.learn("Bflmpsvz")
        #expect(flagged("Ahoj Bflmpsvz").isEmpty)
        let reloaded = try LearnedWords(storeURL: learnedFile, readOnlySources: [])
        #expect(reloaded.contains("Bflmpsvz"))
        try speller.forget("Bflmpsvz")
        #expect(flagged("Ahoj Bflmpsvz") == ["Bflmpsvz"])
    }

    @Test func learnedWordIsNotFlaggedForMissingAccents() throws {
        #expect(flagged("Nemam cas, zavolam ti zitra.").contains("cas"))
        try speller.learn("cas")
        #expect(!flagged("Nemam cas, zavolam ti zitra.").contains("cas"))
    }

    @Test func learnReportsAStoreThatCannotBeWritten() throws {
        let unwritable = try BilingualSpeller(
            dictionaryDirectory: Self.dictionaries,
            learnedWords: LearnedWords(storeURL: URL(fileURLWithPath: "/dev/null/learned.txt"), readOnlySources: [])
        )
        #expect(throws: (any Error).self) { try unwritable.learn("bflmpsvz") }
    }

    @Test func lowercaseLearnedWordIsAcceptedCapitalized() throws {
        try speller.learn("bflmpsvz")
        #expect(flagged("Bflmpsvz je super.").isEmpty)
        try speller.learn("cas")
        #expect(!flagged("Cas je dobrý.").contains("Cas"))
    }

    @Test func capitalizedLearnedWordIsNotAcceptedLowercase() throws {
        try speller.learn("Bflmpsvz")
        #expect(flagged("ahoj bflmpsvz") == ["bflmpsvz"])
    }

    @Test func lowercaseProperNounGetsCapitalizedGuess() {
        #expect(flagged("See you on monday.") == ["monday"])
        #expect(speller.guesses(for: "monday", context: Self.english).first == "Monday")
        #expect(speller.guesses(for: "praha", context: Self.czech).first == "Praha")
        #expect(!speller.guesses(for: "cas", context: Self.czech).contains("Cas"))
    }

    @Test func acceptsDecomposedText() {
        #expect(flagged("Příliš žluťoučký kůň úpěl ďábelské ódy.".decomposedStringWithCanonicalMapping).isEmpty)
    }

    @Test(arguments: ["Mám rad kafe.", "To je dobrý nápad, který jsi mel.", "Jsem spokojený s praci."])
    func decomposedTextKeepsSentenceContext(_ sentence: String) {
        let decomposed = sentence.decomposedStringWithCanonicalMapping
        #expect(flagged(decomposed) == flagged(sentence))
        let word = flagged(sentence).last ?? ""
        let composedGuesses = speller.guesses(for: word)
        _ = speller.misspellings(in: decomposed)
        #expect(speller.guesses(for: word) == composedGuesses)
    }
}

private final class FakeNativeGuesses: NativeGuessProviding {
    let answer: NativeGuesses?
    private(set) var prefetched: [String] = []
    init(answer: NativeGuesses?) { self.answer = answer }
    func cachedGuesses(for word: String) -> NativeGuesses? { answer }
    func prefetch(_ words: [String]) { prefetched += words }
}

@Suite(.serialized) struct BilingualSpellerNativeGuessTests {
    private func speller(_ native: FakeNativeGuesses) throws -> BilingualSpeller {
        try BilingualSpeller(
            dictionaryDirectory: BilingualSpellerTests.dictionaries,
            learnedWords: LearnedWords(storeURL: URL(fileURLWithPath: "/dev/null"), readOnlySources: []),
            nativeGuesses: native
        )
    }

    @Test func includesNativeCandidates() throws {
        let s = try speller(FakeNativeGuesses(answer: NativeGuesses(czech: ["bflmpsvy"], english: [])))
        #expect(s.guesses(for: "bflmpsvz", context: BilingualSpellerTests.czech).contains("bflmpsvy"))
    }

    @Test func worksWithoutNativeGuesses() throws {
        #expect(try speller(FakeNativeGuesses(answer: nil)).guesses(for: "protoze", context: BilingualSpellerTests.czech).first == "protože")
        let empty = FakeNativeGuesses(answer: NativeGuesses(czech: [], english: []))
        #expect(try speller(empty).guesses(for: "protoze", context: BilingualSpellerTests.czech).first == "protože")
    }

    @Test func prefetchesNativeGuessesForFlaggedWords() throws {
        let native = FakeNativeGuesses(answer: nil)
        _ = try speller(native).misspellings(in: "Zitra pujdeme do kina.")
        #expect(native.prefetched == ["Zitra", "pujdeme"])
    }

    @Test func prefetchesOnCacheMissSoTheNextRequestIsNative() throws {
        let native = FakeNativeGuesses(answer: nil)
        _ = try speller(native).guesses(for: "pujdeme", context: BilingualSpellerTests.czech)
        #expect(native.prefetched == ["pujdeme"])
    }
}
