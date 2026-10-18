import AppKit

// Usage: spellprobe [language-id | auto] < sentences.txt
// Checks each line through NSSpellChecker like a real app does and prints the misspellings with their guesses.
// "auto" uses macOS automatic language identification (the native default).

let language = CommandLine.arguments.dropFirst().first ?? "mul"
let isAutomatic = language == "auto"
// A person sees the squiggle before right-clicking; CzEnSpell prefetches guesses in that gap.
let rightClickDelay: TimeInterval = 0.3
let shownGuesses = 4

func readSentences() -> [String] {
    var sentences: [String] = []
    while let line = readLine(strippingNewline: true) {
        if !line.isEmpty { sentences.append(line) }
    }
    return sentences
}

let sentences = readSentences()

/// Uses the unified check, the path where macOS picks the language itself.
func automaticMisspellings(in sentence: String, checker: NSSpellChecker) -> [String] {
    let nsSentence = sentence as NSString
    var orthography: NSOrthography?
    var wordCount = 0
    let results = checker.check(
        sentence, range: NSRange(location: 0, length: nsSentence.length),
        types: NSTextCheckingResult.CheckingType.spelling.rawValue, options: nil,
        inSpellDocumentWithTag: 0, orthography: &orthography, wordCount: &wordCount
    )
    let detected = orthography?.dominantLanguage ?? "?"
    // The results also carry an .orthography result spanning the whole sentence; only .spelling ones are misspellings.
    return results.filter { $0.resultType == .spelling }.map { result in
        let guesses =
            checker.guesses(
                forWordRange: result.range, in: sentence, language: orthography?.dominantLanguage, inSpellDocumentWithTag: 0
            ) ?? []
        return "\(nsSentence.substring(with: result.range)) [\(detected)] -> \(guesses.prefix(shownGuesses).joined(separator: ", "))"
    }
}

/// Walks the sentence with checkSpelling for one fixed language, then asks for guesses.
func misspellings(in sentence: String, checker: NSSpellChecker) -> [String] {
    let nsSentence = sentence as NSString
    var start = 0
    var ranges: [NSRange] = []
    while start < nsSentence.length {
        let range = checker.checkSpelling(
            of: sentence, startingAt: start, language: language, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil
        )
        guard range.location != NSNotFound, range.location >= start else { break }
        ranges.append(range)
        start = NSMaxRange(range)
    }
    if !ranges.isEmpty { Thread.sleep(forTimeInterval: rightClickDelay) }
    return ranges.map { range in
        let guesses = checker.guesses(forWordRange: range, in: sentence, language: language, inSpellDocumentWithTag: 0) ?? []
        return "\(nsSentence.substring(with: range)) -> \(guesses.prefix(shownGuesses).joined(separator: ", "))"
    }
}

func probe() {
    let checker = NSSpellChecker.shared
    guard isAutomatic || checker.availableLanguages.contains(language) else {
        print("FAIL: '\(language)' not in availableLanguages")
        exit(1)
    }
    if isAutomatic {
        print("Automatic language identification over: \(checker.userPreferredLanguages.joined(separator: ", "))")
    }
    for sentence in sentences {
        let start = Date()
        let found =
            isAutomatic
            ? automaticMisspellings(in: sentence, checker: checker)
            : misspellings(in: sentence, checker: checker)
        let elapsedMilliseconds = Int(Date().timeIntervalSince(start) * 1000)
        print("\(sentence)  [\(elapsedMilliseconds) ms]")
        found.forEach { print("    \($0)") }
        if found.isEmpty { print("    (no misspellings)") }
    }
    exit(0)
}

// NSSpellChecker only sees third-party spell servers inside a running NSApplication,
// and discovers them asynchronously after it starts.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { probe() }
DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
    print("FAIL: timed out")
    exit(2)
}
app.run()
