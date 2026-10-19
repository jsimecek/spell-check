import Testing

@testable import SpellCore

@Suite struct ErrorModelTests {
    private func cost(_ typed: String, _ candidate: String) -> Double {
        ErrorModel.cost(typed: typed, candidate: candidate)
    }

    @Test func identicalAndCaseOnlyAreFree() {
        #expect(cost("praha", "praha") == 0)
        #expect(cost("monday", "Monday") == 0)
    }

    @Test func accentsLeftOutAreFree() {
        #expect(cost("prace", "práce") == 0)
        #expect(cost("muzes", "můžeš") == 0)
    }

    @Test func accentsTypedCount() {
        #expect(cost("jistí", "jisti") == ErrorModel.wrongAccent)
        #expect(cost("sledováný", "sledovány") == ErrorModel.wrongAccent)
        #expect(cost("sledováný", "sledování") == ErrorModel.iy)
    }

    @Test func iAndYAreCheap() {
        #expect(cost("mislím", "myslím") == ErrorModel.iy)
        #expect(cost("jistí", "jistý") == ErrorModel.iy)
        #expect(cost("mislim", "myslím") == ErrorModel.iy)
    }

    @Test func keyboardLayoutSwapIsCheap() {
        #expect(cost("yitra", "zítra") == ErrorModel.layoutSwap)
        #expect(cost("ybraně", "zbraně") < cost("ybraně", "vybrané"))
    }

    @Test func neighbouringKeyIsCheaperThanAnyKey() {
        #expect(cost("nwstane", "nestane") == ErrorModel.nearbyKey)
        #expect(cost("nqstane", "nestane") == 1)
    }

    @Test func doubledLettersAreCheap() {
        #expect(cost("acord", "accord") == ErrorModel.doubledLetter)
        #expect(cost("bboby", "boby") == ErrorModel.doubledLetter)
        #expect(cost("choosen", "chosen") < cost("choosen", "choose"))
    }

    @Test func missingHInChIsCheap() {
        #expect(cost("necám", "nechám") == ErrorModel.digraph)
        #expect(cost("necám", "nechám") < cost("necám", "nemám"))
    }

    @Test func transpositionIsCheaperThanTwoEdits() {
        #expect(cost("teh", "the") == ErrorModel.transposition)
    }

    @Test func splitsCostMoreThanADoubledLetter() {
        #expect(cost("absail", "ab-sail") == ErrorModel.hyphenSplit)
        #expect(cost("alot", "a lot") == ErrorModel.wordSplit)
        #expect(cost("asign", "a sign") > cost("asign", "assign"))
    }

    @Test func plainEditsCostOne() {
        #expect(cost("definately", "definitely") == 1)
        #expect(cost("tomorow", "tomorrow") == ErrorModel.doubledLetter)
        #expect(cost("kat", "kot") == 1)
        #expect(cost("kat", "katka") == 2)
    }

    @Test func englishVowelSlipsAreCheaperOnlyForEnglishWords() {
        #expect(ErrorModel.cost(typed: "definately", candidate: "definitely", language: .english) == ErrorModel.englishVowel)
        #expect(ErrorModel.cost(typed: "happend", candidate: "happened", language: .english) == ErrorModel.englishVowelIndel)
        #expect(ErrorModel.cost(typed: "definately", candidate: "definitely", language: .czech) == 1)
        #expect(ErrorModel.cost(typed: "pmoc", candidate: "pomoc", language: .czech) == 1)
    }
}
