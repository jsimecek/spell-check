import AppKit

// Usage: spellprobe [language-id | auto] < sentences.txt
// Exercises spell checking through NSSpellChecker like a real app does.
// "auto" uses macOS automatic language identification (the native default).
let language = CommandLine.arguments.dropFirst().first ?? "mul"
let rightClickDelay: TimeInterval = 0.3
let sentences = (readLine(strippingNewline: true).map { first in
    [first] + Array(sequence(state: (), next: { _ in readLine(strippingNewline: true) }))
} ?? []).filter { !$0.isEmpty }

func misspellings(in sentence: String, checker: NSSpellChecker) -> [String] {
    let ns = sentence as NSString
    if language == "auto" {
        var orthography: NSOrthography?
        var wordCount = 0
        let results = checker.check(
            sentence, range: NSRange(location: 0, length: ns.length),
            types: NSTextCheckingResult.CheckingType.spelling.rawValue, options: nil,
            inSpellDocumentWithTag: 0, orthography: &orthography, wordCount: &wordCount
        )
        let detected = orthography?.dominantLanguage ?? "?"
        return results.map { result in
            let guesses = checker.guesses(
                forWordRange: result.range, in: sentence, language: orthography?.dominantLanguage, inSpellDocumentWithTag: 0
            ) ?? []
            return "\(ns.substring(with: result.range)) [\(detected)] -> \(guesses.prefix(4).joined(separator: ", "))"
        }
    }
    var start = 0
    var ranges: [NSRange] = []
    while start < ns.length {
        let range = checker.checkSpelling(
            of: sentence, startingAt: start, language: language, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil
        )
        guard range.location != NSNotFound, range.location >= start else { break }
        ranges.append(range)
        start = range.location + range.length
    }
    // A person sees the squiggle before right-clicking; CzEnSpell prefetches guesses in that gap.
    if !ranges.isEmpty { Thread.sleep(forTimeInterval: rightClickDelay) }
    return ranges.map { range in
        let guesses = checker.guesses(forWordRange: range, in: sentence, language: language, inSpellDocumentWithTag: 0) ?? []
        return "\(ns.substring(with: range)) -> \(guesses.prefix(4).joined(separator: ", "))"
    }
}

func probe() {
    let checker = NSSpellChecker.shared
    guard language == "auto" || checker.availableLanguages.contains(language) else {
        print("FAIL: '\(language)' not in availableLanguages")
        exit(1)
    }
    if language == "auto" {
        print("Automatic language identification over: \(checker.userPreferredLanguages.joined(separator: ", "))")
    }
    for sentence in sentences {
        let began = Date()
        let found = misspellings(in: sentence, checker: checker)
        let ms = Int(Date().timeIntervalSince(began) * 1000)
        print("\(sentence)  [\(ms) ms]")
        found.forEach { print("    \($0)") }
        if found.isEmpty { print("    (no misspellings)") }
    }
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
// Spell servers are discovered asynchronously after the app starts.
DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { probe() }
DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
    print("FAIL: timed out")
    exit(2)
}
app.run()
