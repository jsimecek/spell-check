import Foundation

public enum LearnedWordsError: Error {
    /// The store exists but could not be read, so saving would overwrite the words in it.
    case storeUnreadable
}

/// User-learned words: our own newline-separated store plus read-only sources such as
/// macOS's ~/Library/Spelling/LocalDictionary. Read-only words the user forgot are kept in
/// the store as "!word" lines so they stay forgotten. Soft hyphens are left out of every word, as checks do.
public final class LearnedWords {
    private static let forgottenMarker = "!"

    private let storeURL: URL
    private let isStoreWritable: Bool
    private var ownWords: Set<String>
    private var forgottenWords: Set<String>
    private let sourceWords: Set<String>
    /// Source words the user has not forgotten.
    private var readOnlyWords: Set<String>

    public init(storeURL: URL, readOnlySources: [URL]) throws {
        self.storeURL = storeURL
        let store = Self.loadStore(storeURL)
        isStoreWritable = store.isWritable
        ownWords = store.lines.filter { !$0.hasPrefix(Self.forgottenMarker) }
        forgottenWords = Set(store.lines.filter { $0.hasPrefix(Self.forgottenMarker) }.map { String($0.dropFirst()) })
        sourceWords = readOnlySources.reduce(into: []) { $0.formUnion(Self.loadSource($1)) }
        readOnlyWords = sourceWords.subtracting(forgottenWords)
    }

    var all: Set<String> { ownWords.union(readOnlyWords) }

    /// Like Hunspell, a word learned in lowercase is also accepted with an initial capital, not the reverse.
    func contains(_ word: String) -> Bool {
        if isLearned(word) { return true }
        let uncapitalized = word.lowercasingFirstLetter()
        return uncapitalized != word && isLearned(uncapitalized)
    }

    /// Ignores words that cannot be stored as one plain line, so callers cannot inject or forget other words.
    func add(_ word: String) throws {
        let word = word.removingSoftHyphens
        guard !word.isEmpty, !word.hasPrefix(Self.forgottenMarker), !word.contains(where: \.isNewline) else { return }
        let isNew = ownWords.insert(word).inserted
        let wasForgotten = forgottenWords.remove(word) != nil
        guard isNew || wasForgotten else { return }
        try save()
    }

    /// Forgetting "Foo" forgets the learned "foo" that made it acceptable.
    func remove(_ word: String) throws {
        let word = word.removingSoftHyphens
        var changed = false
        for form in Set([word, word.lowercasingFirstLetter()]) {
            if ownWords.remove(form) != nil { changed = true }
            readOnlyWords.remove(form)
            // Also when re-learned after an earlier forget, so the source can't bring it back.
            if sourceWords.contains(form), forgottenWords.insert(form).inserted { changed = true }
        }
        guard changed else { return }
        try save()
    }

    private func isLearned(_ form: String) -> Bool {
        ownWords.contains(form) || readOnlyWords.contains(form)
    }

    private func save() throws {
        guard isStoreWritable else { throw LearnedWordsError.storeUnreadable }
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lines = ownWords.sorted() + forgottenWords.sorted().map { Self.forgottenMarker + $0 }
        try (lines.joined(separator: "\n") + "\n").write(to: storeURL, atomically: true, encoding: .utf8)
    }

    /// A missing store is empty and writable; one that exists but can't be read or decoded stays untouched.
    private static func loadStore(_ url: URL) -> (lines: Set<String>, isWritable: Bool) {
        do {
            guard let text = String(data: try Data(contentsOf: url), encoding: .utf8) else { return ([], false) }
            return (nonEmptyLines(of: text), true)
        } catch CocoaError.fileReadNoSuchFile {
            return ([], true)
        } catch {
            return ([], false)
        }
    }

    /// An unreadable source simply contributes no words.
    private static func loadSource(_ url: URL) -> Set<String> {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return nonEmptyLines(of: text)
    }

    private static func nonEmptyLines(of text: String) -> Set<String> {
        // split omits empty lines by default; a line of soft hyphens only is empty too.
        Set(text.split(whereSeparator: \.isNewline).map { String($0).removingSoftHyphens }.filter { !$0.isEmpty })
    }
}
