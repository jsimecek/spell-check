import Testing
@testable import SpellCore

@Suite struct LanguageDetectorTests {
    @Test(arguments: [
        "Dneska nevim jestli zitra prijdu, protoze mam praci.",
        "Ahoj, prosim te muzes mi to poslat?",
        "Mám rád kafe a nevím proč.",
    ])
    func detectsCzechWithAndWithoutDiacritics(_ text: String) {
        #expect(LanguageDetector.detect(text) == .czech)
    }

    @Test func detectsEnglish() {
        #expect(LanguageDetector.detect("I definately recieve the mail tomorrow morning.") == .english)
    }

    @Test func returnsNilForTooShortText() {
        #expect(LanguageDetector.detect("ok") == nil)
    }
}
