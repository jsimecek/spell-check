import Testing

@testable import SpellCore

@Suite struct ColloquialCzechTests {
    @Test(arguments: [
        ("kterej", "který"), ("dobrej", "dobrý"), ("dobrejch", "dobrých"), ("dobrejm", "dobrým"),
        ("vokno", "okno"), ("Vokno", "Okno"),
    ])
    func rewritesToStandardForm(_ word: String, _ expected: String) {
        #expect(ColloquialCzech.standardForms(of: word).contains(expected))
    }

    @Test func leavesOtherWordsAlone() {
        #expect(ColloquialCzech.standardForms(of: "okno").isEmpty)
    }
}
