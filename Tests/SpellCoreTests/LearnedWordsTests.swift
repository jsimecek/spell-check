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

    @Test func failedWriteOfMissingStoreIsReported() throws {
        // Missing store on the read-only system volume: loads fine, saving fails.
        let readOnlyVolume = URL(fileURLWithPath: "/System/czen-\(UUID().uuidString)/learned.txt")
        let learned = try LearnedWords(storeURL: readOnlyVolume, readOnlySources: [])
        #expect(throws: CocoaError.self) { try learned.add("nove") }
    }
}
