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
    /// Hunspell rejects longer words without a lookup (`MAXWORDUTF8LEN` in hunspell.cxx).
    static let maxWordBytes = 299

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
        Hunspell_spell(handle, Self.lookupForm(of: word)) != 0
    }

    func suggestions(for word: String) -> [String] {
        var list: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        let count = Hunspell_suggest(handle, &list, Self.lookupForm(of: word))
        defer { Hunspell_free_list(handle, &list, count) }
        guard let list, count > 0 else { return [] }
        return (0..<Int(count)).compactMap { list[$0].map { String(cString: $0) } }
    }

    // Hunspell compares raw bytes and the dictionaries are NFC without soft hyphens (pasted "po\u{AD}slat").
    private static func lookupForm(of word: String) -> String {
        word.removingSoftHyphens.precomposedStringWithCanonicalMapping
    }
}
