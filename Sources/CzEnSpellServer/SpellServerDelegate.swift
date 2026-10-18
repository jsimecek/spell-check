import Foundation
import SpellCore
import os

/// Bridges NSSpellServer callbacks to BilingualSpeller. Never logs user text.
final class SpellServerDelegate: NSObject, NSSpellServerDelegate {
    private let speller: BilingualSpeller
    private let languageID: String
    private let log = Logger(subsystem: "io.github.jirisimecek.CzEnSpell", category: "server")

    init(speller: BilingualSpeller, languageID: String) {
        self.speller = speller
        self.languageID = languageID
    }

    func spellServer(
        _ sender: NSSpellServer, findMisspelledWordIn stringToCheck: String, language: String,
        wordCount: UnsafeMutablePointer<Int>, countOnly: Bool
    ) -> NSRange {
        let words = WordScanner.words(in: stringToCheck)
        if countOnly {
            wordCount.pointee = words.count
            return NSRange(location: NSNotFound, length: 0)
        }
        guard let first = speller.misspellings(in: stringToCheck).first else {
            wordCount.pointee = words.count
            return NSRange(location: NSNotFound, length: 0)
        }
        wordCount.pointee = words.filter { $0.location <= first.location }.count
        return first
    }

    func spellServer(
        _ sender: NSSpellServer, check stringToCheck: String, offset: Int, types checkingTypes: NSTextCheckingTypes,
        options: [String: Any]? = nil, orthography: NSOrthography?, wordCount: UnsafeMutablePointer<Int>
    ) -> [NSTextCheckingResult]? {
        wordCount.pointee = WordScanner.words(in: stringToCheck).count
        guard checkingTypes & NSTextCheckingResult.CheckingType.spelling.rawValue != 0 else { return [] }
        let start = Date()
        // Spelling results only: no .correction results, so nothing is auto-replaced while typing.
        var results = speller.misspellings(in: stringToCheck).map {
            NSTextCheckingResult.spellCheckingResult(range: NSRange(location: $0.location + offset, length: $0.length))
        }
        let misspelled = results.count
        // Without an orthography the app detects the language itself and asks Apple's English for the
        // right-click guesses; claiming our language routes those requests back to us.
        let orthography = NSOrthography(dominantScript: "Latn", languageMap: ["Latn": [languageID]])
        let whole = NSRange(location: offset, length: (stringToCheck as NSString).length)
        results.append(NSTextCheckingResult.orthographyCheckingResult(range: whole, orthography: orthography))
        log.debug("check: \(misspelled) misspellings in \(Date().timeIntervalSince(start) * 1000, format: .fixed(precision: 1)) ms")
        return results
    }

    func spellServer(_ sender: NSSpellServer, suggestGuessesForWord word: String, inLanguage language: String) -> [String]? {
        let start = Date()
        let guesses = speller.guesses(for: word)
        log.debug("guesses: \(guesses.count) in \(Date().timeIntervalSince(start) * 1000, format: .fixed(precision: 1)) ms")
        return guesses
    }

    func spellServer(_ sender: NSSpellServer, didLearnWord word: String, inLanguage language: String) {
        do { try speller.learn(word) } catch { logSaveFailure("learn", error) }
    }

    func spellServer(_ sender: NSSpellServer, didForgetWord word: String, inLanguage language: String) {
        do { try speller.forget(word) } catch { logSaveFailure("forget", error) }
    }

    /// Domain and code only, so no file paths or user text reach the log.
    private func logSaveFailure(_ action: String, _ error: Error) {
        let error = error as NSError
        log.error("\(action, privacy: .public): saving learned words failed: \(error.domain, privacy: .public) \(error.code)")
    }
}
