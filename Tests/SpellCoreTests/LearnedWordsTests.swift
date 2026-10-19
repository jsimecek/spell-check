import Foundation
import Testing

@testable import SpellCore

@Suite struct LearnedWordsTests {
    let store = FileManager.default.temporaryDirectory.appendingPathComponent("czen-learned-\(UUID().uuidString).txt")

    /// A read-only word list like macOS's LocalDictionary.
    private func readOnlySource(_ contents: String) throws -> URL {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("czen-local-\(UUID().uuidString)")
        try contents.write(to: source, atomically: true, encoding: .utf8)
        return source
    }

    @Test func unreadableStoreIsNeverOverwritten() throws {
        let original = Data([0x63, 0xE8, 0x0A])  // "c\u{E8}\n": CP1250 "č", invalid UTF-8
        try original.write(to: store)
        let learned = try LearnedWords(storeURL: store, readOnlySources: [])
        #expect(throws: (any Error).self) { try learned.add("nove") }
        #expect(learned.contains("nove"))
        #expect(try Data(contentsOf: store) == original)
    }

    @Test func missingStoreIsCreatedOnFirstAdd() throws {
        let learned = try LearnedWords(storeURL: store, readOnlySources: [])
        try learned.add("nove")
        #expect(try String(contentsOf: store, encoding: .utf8) == "nove\n")
    }

    @Test func forgottenReadOnlyWordStaysForgottenAfterReload() throws {
        let source = try readOnlySource("foo\nbar\n")
        try LearnedWords(storeURL: store, readOnlySources: [source]).remove("foo")
        let reloaded = try LearnedWords(storeURL: store, readOnlySources: [source])
        #expect(!reloaded.contains("foo"))
        #expect(reloaded.contains("bar"))
        try reloaded.add("foo")
        #expect(try LearnedWords(storeURL: store, readOnlySources: [source]).contains("foo"))
    }

    @Test func relearnedReadOnlyWordForgottenAgainStaysForgottenAfterReload() throws {
        let source = try readOnlySource("foo\n")
        let learned = try LearnedWords(storeURL: store, readOnlySources: [source])
        try learned.remove("foo")
        try learned.add("foo")
        try learned.remove("foo")
        #expect(!learned.contains("foo"))
        #expect(!(try LearnedWords(storeURL: store, readOnlySources: [source]).contains("foo")))
    }

    @Test func forgettingCapitalizedFormForgetsLearnedLowercaseWord() throws {
        let learned = try LearnedWords(storeURL: store, readOnlySources: [])
        try learned.add("foo")
        try learned.remove("Foo")
        #expect(!learned.contains("Foo"))
        #expect(!(try LearnedWords(storeURL: store, readOnlySources: []).contains("foo")))
    }

    @Test func forgettingCapitalizedFormForgetsBothStoredForms() throws {
        let learned = try LearnedWords(storeURL: store, readOnlySources: [])
        try learned.add("Foo")
        try learned.add("foo")
        try learned.remove("Foo")
        #expect(!learned.contains("Foo"))
        #expect(!learned.contains("foo"))
        #expect(!(try LearnedWords(storeURL: store, readOnlySources: []).contains("Foo")))
    }

    @Test func forgettingReadOnlyCapitalizedFormAlsoForgetsOwnLowercase() throws {
        let source = try readOnlySource("Foo\n")
        let learned = try LearnedWords(storeURL: store, readOnlySources: [source])
        try learned.add("foo")
        try learned.remove("Foo")
        #expect(!learned.contains("Foo"))
        #expect(!(try LearnedWords(storeURL: store, readOnlySources: [source]).contains("Foo")))
    }

    @Test func wordsThatWouldChangeOtherStoreLinesAreNotLearned() throws {
        let source = try readOnlySource("foo\n")
        let learned = try LearnedWords(storeURL: store, readOnlySources: [source])
        for word in ["!foo", "bar\nbaz", "qux\r\n!foo", ""] {
            try learned.add(word)
            #expect(!learned.contains(word))
        }
        let reloaded = try LearnedWords(storeURL: store, readOnlySources: [source])
        #expect(reloaded.contains("foo"))
        #expect(reloaded.all == ["foo"])
    }

    @Test func softHyphensInStoredWordsAreIgnored() throws {
        let source = try readOnlySource("ba\u{AD}r\n")
        try "fo\u{AD}o\n!ba\u{AD}r\n\u{AD}\n".write(to: store, atomically: true, encoding: .utf8)
        let learned = try LearnedWords(storeURL: store, readOnlySources: [source])
        #expect(learned.contains("foo"))
        #expect(!learned.contains("bar"))
        #expect(learned.all == ["foo"])
        try learned.remove("fo\u{AD}o")
        #expect(!learned.contains("foo"))
        #expect(!(try LearnedWords(storeURL: store, readOnlySources: [source]).contains("foo")))
    }

    @Test func softHyphensAreLeftOutOfLearnedWords() throws {
        let learned = try LearnedWords(storeURL: store, readOnlySources: [])
        try learned.add("fo\u{AD}o")
        try learned.add("\u{AD}")
        #expect(learned.contains("foo"))
        #expect(try String(contentsOf: store, encoding: .utf8) == "foo\n")
    }

    @Test func failedWriteOfMissingStoreIsReported() throws {
        // Missing store on the read-only system volume: loads fine, saving fails.
        let readOnlyVolume = URL(fileURLWithPath: "/System/czen-\(UUID().uuidString)/learned.txt")
        let learned = try LearnedWords(storeURL: readOnlyVolume, readOnlySources: [])
        #expect(throws: CocoaError.self) { try learned.add("nove") }
    }
}
