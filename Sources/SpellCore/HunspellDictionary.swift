import CHunspell
import Foundation

public enum SpellCoreError: Error, CustomStringConvertible {
    case missingDictionary(URL)

    public var description: String {
        switch self {
        case .missingDictionary(let url): "Missing dictionary \(url.path). Run scripts/fetch-dictionaries.sh."
        }
    }
}

/// Thin wrapper over the Hunspell C API. Dictionaries must be UTF-8 (`SET UTF-8`).
final class HunspellDictionary {
    private let handle: OpaquePointer

    init(directory: URL, name: String) throws {
        let aff = directory.appendingPathComponent("\(name).aff")
        let dic = directory.appendingPathComponent("\(name).dic")
        for url in [aff, dic] where !FileManager.default.fileExists(atPath: url.path) {
            throw SpellCoreError.missingDictionary(url)
        }
        handle = Hunspell_create(aff.path, dic.path)
    }

    deinit { Hunspell_destroy(handle) }

    func isCorrect(_ word: String) -> Bool {
        Hunspell_spell(handle, word) != 0
    }

    func suggestions(for word: String) -> [String] {
        var list: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        let count = Hunspell_suggest(handle, &list, word)
        defer { Hunspell_free_list(handle, &list, count) }
        guard let list, count > 0 else { return [] }
        return (0..<Int(count)).compactMap { list[$0].map { String(cString: $0) } }
    }

    func add(_ word: String) { Hunspell_add(handle, word) }

    func remove(_ word: String) { Hunspell_remove(handle, word) }
}
