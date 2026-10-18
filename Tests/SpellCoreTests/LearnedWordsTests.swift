import Foundation
import Testing
@testable import SpellCore

@Suite struct LearnedWordsTests {
    let store = FileManager.default.temporaryDirectory.appendingPathComponent("czen-learned-\(UUID().uuidString).txt")

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
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("czen-local-\(UUID().uuidString)")
        try "foo\nbar\n".write(to: source, atomically: true, encoding: .utf8)
        try LearnedWords(storeURL: store, readOnlySources: [source]).remove("foo")
        let reloaded = try LearnedWords(storeURL: store, readOnlySources: [source])
        #expect(!reloaded.contains("foo"))
        #expect(reloaded.contains("bar"))
        try reloaded.add("foo")
        #expect(try LearnedWords(storeURL: store, readOnlySources: [source]).contains("foo"))
    }

    @Test func forgettingCapitalizedFormForgetsLearnedLowercaseWord() throws {
        let learned = try LearnedWords(storeURL: store, readOnlySources: [])
        try learned.add("foo")
        try learned.remove("Foo")
        #expect(!learned.contains("Foo"))
        #expect(!(try LearnedWords(storeURL: store, readOnlySources: []).contains("foo")))
    }

    @Test func failedWriteOfMissingStoreIsReported() throws {
        // Missing store on the read-only system volume: loads fine, saving fails.
        let readOnlyVolume = URL(fileURLWithPath: "/System/czen-\(UUID().uuidString)/learned.txt")
        let learned = try LearnedWords(storeURL: readOnlyVolume, readOnlySources: [])
        #expect(throws: CocoaError.self) { try learned.add("nove") }
    }
}
