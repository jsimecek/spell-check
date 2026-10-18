import Foundation

/// User-learned words: our own newline-separated store plus read-only sources such as
/// macOS's ~/Library/Spelling/LocalDictionary.
public final class LearnedWords {
    private let storeURL: URL
    private var own: Set<String>
    private var readOnly: Set<String>

    public init(storeURL: URL, readOnlySources: [URL]) throws {
        self.storeURL = storeURL
        own = Self.load(storeURL)
        readOnly = readOnlySources.reduce(into: Set<String>()) { $0.formUnion(Self.load($1)) }
    }

    /// Like Hunspell, a word learned in lowercase is also accepted with an initial capital, not the reverse.
    public func contains(_ word: String) -> Bool {
        if own.contains(word) || readOnly.contains(word) { return true }
        let uncapitalized = word.prefix(1).lowercased() + word.dropFirst()
        return uncapitalized != word && (own.contains(uncapitalized) || readOnly.contains(uncapitalized))
    }

    public var all: Set<String> { own.union(readOnly) }

    public func add(_ word: String) throws {
        guard own.insert(word).inserted else { return }
        try save()
    }

    public func remove(_ word: String) throws {
        readOnly.remove(word)
        guard own.remove(word) != nil else { return }
        try save()
    }

    private func save() throws {
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try (own.sorted().joined(separator: "\n") + "\n").write(to: storeURL, atomically: true, encoding: .utf8)
    }

    private static func load(_ url: URL) -> Set<String> {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Set(text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty })
    }
}
