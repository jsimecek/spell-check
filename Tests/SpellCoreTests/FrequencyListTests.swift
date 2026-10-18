import Foundation
import Testing
@testable import SpellCore

@Suite struct FrequencyListTests {
    let list: FrequencyList

    init() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("freq-\(UUID().uuidString).txt")
        try "to 1000\nkterý 500\nkteré 400\nterč 10\npráci 100\n".write(to: url, atomically: true, encoding: .utf8)
        list = try FrequencyList(url: url)
    }

    @Test func findsNeighborsIgnoringDiacritics() {
        #expect(Set(list.neighbors(of: "kterej", maxDistance: 2)) == ["který", "které"])
    }

    @Test func neighborsFollowCapitalization() {
        #expect(list.neighbors(of: "Praci", maxDistance: 1) == ["Práci"])
    }
}
