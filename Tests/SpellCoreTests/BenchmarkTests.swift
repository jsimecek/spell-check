import Foundation
import Testing

@testable import SpellCore

/// Opt-in quality benchmark: `CZEN_EVAL=1 swift test -c release -Xswiftc -enable-testing --filter BenchmarkTests`.
/// Even rows tune, odd rows are the holdout that the floors guard. English lists need scripts/fetch-benchmark.sh.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CZEN_EVAL"] == "1"))
struct BenchmarkTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let data = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Benchmark")
    static let fetched = root.appendingPathComponent("Benchmarks")

    /// Minimum holdout top-1 (%) per guess set; language and false positives have their own floors.
    static let top1Floors: [String: Double] = [
        "cs-strip": 96, "cs-typo": 80, "cs-strip+typo": 78, "cs-i/y": 94, "cs-y/z": 92,
        "cs-handwritten": 95, "en-handwritten": 93, "en-wikipedia": 85, "en-aspell": 60,
    ]
    static let languageFloor = 97.0
    static let maxFalsePositives = 1

    struct Case {
        let typed: String
        let expected: String
        let sentence: String?
    }

    struct Score {
        var count = 0
        var top1 = 0
        var top5 = 0
        var notFlagged = 0
        var milliseconds: [Double] = []
        var failures: [String] = []

        var top1Percent: Double { count == 0 ? 0 : 100 * Double(top1) / Double(count) }
        var top5Percent: Double { count == 0 ? 0 : 100 * Double(top5) / Double(count) }
    }

    let speller: BilingualSpeller

    init() throws {
        speller = try BilingualSpeller(
            dictionaryDirectory: BilingualSpellerTests.dictionaries,
            learnedWords: LearnedWords(storeURL: URL(fileURLWithPath: "/dev/null"), readOnlySources: [])
        )
    }

    @Test func guesses() throws {
        var sets: [(String, [Case], Language)] = []
        sets += try SyntheticCzech.sets(from: BilingualSpellerTests.dictionaries.appendingPathComponent("cs_50k.txt"), speller: speller)
            .map { ($0.0, $0.1, Language.czech) }
        sets.append(("cs-handwritten", try Self.cases(Self.data.appendingPathComponent("cs-misspellings.txt")), .czech))
        sets.append(("en-handwritten", try Self.cases(Self.data.appendingPathComponent("en-misspellings.txt")), .english))
        if let wikipedia = try? Self.wikipediaCases() { sets.append(("en-wikipedia", wikipedia, .english)) }
        if let aspell = try? Self.aspellCases() { sets.append(("en-aspell", aspell, .english)) }
        if sets.count < 9 { print("BENCH note: English lists missing, run scripts/fetch-benchmark.sh") }

        for (name, cases, language) in sets {
            var halves = [Score(), Score()]
            for (index, testCase) in cases.enumerated() {
                score(testCase, language: language, into: &halves[index % 2])
            }
            for (half, score) in zip(["tune", "holdout"], halves) {
                let average = score.milliseconds.reduce(0, +) / Double(max(score.milliseconds.count, 1))
                print(
                    "BENCH \(name) \(half): n=\(score.count) top1=\(Self.format(score.top1Percent))% "
                        + "top5=\(Self.format(score.top5Percent))% notFlagged=\(score.notFlagged) "
                        + "avg=\(Self.format(average))ms max=\(Self.format(score.milliseconds.max() ?? 0))ms"
                )
                if ProcessInfo.processInfo.environment["CZEN_EVAL_VERBOSE"] == "1" {
                    for failure in score.failures { print("  MISS \(name) \(half): \(failure)") }
                }
            }
            if let floor = Self.top1Floors[name] {
                #expect(halves[1].top1Percent >= floor, "\(name) holdout top-1 below floor")
            }
        }
    }

    @Test func sentenceLanguage() throws {
        let lines = try Self.lines(Self.data.appendingPathComponent("language-sentences.txt"))
        var correct = [0, 0]
        var total = [0, 0]
        for (index, line) in lines.enumerated() {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            let expected = Language(rawValue: parts[0])
            let detected = speller.language(ofSentence: parts[1])
            total[index % 2] += 1
            if detected == expected {
                correct[index % 2] += 1
            } else if ProcessInfo.processInfo.environment["CZEN_EVAL_VERBOSE"] == "1" {
                print("  MISS language: \(parts[1]) -> \(detected?.rawValue ?? "nil")")
            }
        }
        for (index, half) in ["tune", "holdout"].enumerated() {
            print("BENCH language \(half): \(correct[index])/\(total[index])")
        }
        #expect(100 * Double(correct[1]) / Double(total[1]) >= Self.languageFloor)
    }

    @Test func falsePositivesAndCheckSpeed() throws {
        let sentences = try Self.lines(Self.data.appendingPathComponent("correct-sentences.txt"))
        var falsePositives: [String] = []
        for sentence in sentences {
            falsePositives += speller.misspellings(in: sentence).map { (sentence as NSString).substring(with: $0) }
        }
        print("BENCH false positives: \(falsePositives.count) \(falsePositives)")
        #expect(falsePositives.count <= Self.maxFalsePositives)

        let labelled = try Self.lines(Self.data.appendingPathComponent("language-sentences.txt"))
            .map { $0.split(separator: "\t", maxSplits: 1).map(String.init) }
        let english = labelled.filter { $0[0] == "en" }.map { $0[1] }.joined(separator: " ")
        // A fresh speller has empty caches, as after a restart.
        let coldSpeller = try BilingualSpeller(
            dictionaryDirectory: BilingualSpellerTests.dictionaries,
            learnedWords: LearnedWords(storeURL: URL(fileURLWithPath: "/dev/null"), readOnlySources: [])
        )
        let coldStart = Date()
        _ = coldSpeller.misspellings(in: english)
        print("BENCH cold check (en): \(Self.format(Date().timeIntervalSince(coldStart) * 1000)) ms")

        let paragraph = labelled.map { $0[1] }.joined(separator: " ")
        _ = speller.misspellings(in: paragraph)
        let runs = 5
        let start = Date()
        // A fresh word each run keeps caches from hiding the cost of a new check.
        for run in 0..<runs { _ = speller.misspellings(in: paragraph + " slovo\(String(repeating: "x", count: run))") }
        let milliseconds = Date().timeIntervalSince(start) * 1000 / Double(runs)
        print("BENCH check: \(Self.format(milliseconds)) ms for \((paragraph as NSString).length) UTF-16 units")
    }

    // MARK: - Scoring

    /// With a sentence, the word must be flagged there first and gets its remembered context.
    private func score(_ testCase: Case, language: Language, into score: inout Score) {
        var typed = testCase.typed
        var expected = testCase.expected
        if let sentence = testCase.sentence {
            let nsSentence = sentence as NSString
            let range = nsSentence.range(of: testCase.typed, options: .caseInsensitive)
            guard range.location != NSNotFound else { return }
            typed = nsSentence.substring(with: range)
            if typed.first?.isUppercase == true { expected = expected.uppercasingFirstLetter() }
            score.count += 1
            guard speller.misspellings(in: sentence).contains(range) else {
                score.notFlagged += 1
                score.failures.append("\(typed) not flagged in: \(sentence)")
                return
            }
        } else {
            guard !speller.isCorrect(typed) else { return }
            score.count += 1
        }
        let start = Date()
        let guesses =
            testCase.sentence == nil
            ? speller.guesses(for: typed, context: WordContext(language: language, left: nil, right: nil))
            : speller.guesses(for: typed)
        score.milliseconds.append(Date().timeIntervalSince(start) * 1000)
        if guesses.first == expected { score.top1 += 1 }
        if guesses.contains(expected) { score.top5 += 1 }
        if guesses.first != expected { score.failures.append("\(typed) -> \(expected), got \(guesses.prefix(3))") }
    }

    // MARK: - Data

    static func lines(_ url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline).map(String.init)
            .filter { !$0.hasPrefix("#") }
    }

    static func cases(_ url: URL) throws -> [Case] {
        try lines(url).map { line in
            let parts = line.split(separator: "\t").map(String.init)
            return Case(typed: parts[0], expected: parts[1], sentence: parts.count > 2 ? parts[2] : nil)
        }
    }

    /// " typo->correct" lines; entries with several or multi-word corrections are skipped.
    static func wikipediaCases() throws -> [Case] {
        let text = try String(contentsOf: fetched.appendingPathComponent("wikipedia-misspellings.txt"), encoding: .utf8)
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: "->")
            guard parts.count == 2, !parts[1].contains(","), !parts[1].contains(" "), !parts[0].isEmpty else { return nil }
            return Case(typed: parts[0], expected: parts[1], sentence: nil)
        }
    }

    /// "$correct" followed by its misspellings, one per line.
    static func aspellCases() throws -> [Case] {
        let text = try String(contentsOf: fetched.appendingPathComponent("aspell.dat"), encoding: .utf8)
        var cases: [Case] = []
        var expected = ""
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("$") {
                expected = String(line.dropFirst())
            } else if !expected.contains("_") {
                cases.append(Case(typed: String(line), expected: expected, sentence: nil))
            }
        }
        return cases
    }

    static func format(_ value: Double) -> String { String(format: "%.1f", value) }
}

/// Deterministic Czech typos built from frequent dictionary words.
enum SyntheticCzech {
    private static let keyboardRows = ["qwertzuiop", "asdfghjkl", "yxcvbnm"].map(Array.init)

    static func sets(from frequencyList: URL, speller: BilingualSpeller) throws -> [(String, [BenchmarkTests.Case])] {
        let words = try String(contentsOf: frequencyList, encoding: .utf8).split(separator: "\n")
            .map { String($0.split(separator: " ")[0]) }
            .enumerated()
            .filter { rank, word in
                rank > 300 && rank < 30000 && rank % 50 == 0 && word.count >= 4 && word.allSatisfy(\.isLetter)
                    && speller.isCorrect(word)
            }
            .map(\.element)
        let accented = words.filter(\.hasDiacritics)
        var random = SplitMix(seed: 42)
        func cases(_ pairs: [(String, String)]) -> [BenchmarkTests.Case] {
            pairs.filter { $0.0 != $0.1 }.map { BenchmarkTests.Case(typed: $0.0, expected: $0.1, sentence: nil) }
        }
        return [
            ("cs-strip", cases(accented.map { (strip($0), $0) })),
            ("cs-typo", cases(words.map { (typo($0, &random), $0) })),
            ("cs-strip+typo", cases(accented.map { (typo(strip($0), &random), $0) })),
            ("cs-i/y", cases(words.compactMap(swapIY))),
            ("cs-y/z", cases(words.compactMap { word in
                guard word.contains("z") || word.contains("y") else { return nil }
                return (String(word.map { $0 == "z" ? "y" : $0 == "y" ? "z" : $0 }), word)
            })),
        ]
    }

    private static func strip(_ word: String) -> String {
        word.folding(options: .diacriticInsensitive, locale: nil)
    }

    private static func swapIY(_ word: String) -> (String, String)? {
        for (from, to) in [("ý", "í"), ("y", "i"), ("í", "ý")] {
            if let range = word.range(of: from) { return (word.replacingCharacters(in: range, with: to), word) }
        }
        return nil
    }

    private static func neighbors(of character: Character) -> [Character] {
        for (row, keys) in keyboardRows.enumerated() {
            guard let column = keys.firstIndex(of: character) else { continue }
            var result: [Character] = []
            for nearRow in [row - 1, row, row + 1] where keyboardRows.indices.contains(nearRow) {
                for nearColumn in [column - 1, column, column + 1] where keyboardRows[nearRow].indices.contains(nearColumn) {
                    if nearRow != row || nearColumn != column { result.append(keyboardRows[nearRow][nearColumn]) }
                }
            }
            return result
        }
        return []
    }

    /// One substitution by a neighbouring key, deletion, transposition or neighbouring-key insertion.
    private static func typo(_ word: String, _ random: inout SplitMix) -> String {
        var letters = Array(word)
        let kind = random.next(4)
        let index = random.next(letters.count)
        let nearby = neighbors(of: Character(strip(String(letters[index]))))
        switch kind {
        case 0 where !nearby.isEmpty: letters[index] = nearby[random.next(nearby.count)]
        case 1 where letters.count > 3: letters.remove(at: index)
        case 2 where index < letters.count - 1: letters.swapAt(index, index + 1)
        case 3 where !nearby.isEmpty: letters.insert(nearby[random.next(nearby.count)], at: index)
        default: letters.insert(letters[index], at: index)
        }
        return String(letters)
    }
}

struct SplitMix {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next(_ bound: Int) -> Int {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Int((z ^ (z >> 31)) % UInt64(bound))
    }
}
