/// How plausibly `typed` is a slip for `candidate`, in edits; lower is likelier.
/// Accents left out are free, but accents the user typed count, and common Czech and keyboard
/// slips (i/y, y/z layout, neighbouring keys, doubled letters) cost less than a random edit.
enum ErrorModel {
    static let wrongAccent = 0.5
    static let iy = 0.5
    /// y and z swap places between the Czech QWERTZ and the US QWERTY layout.
    static let layoutSwap = 0.5
    static let nearbyKey = 0.9
    static let doubledLetter = 0.5
    /// "c" typed for "ch".
    static let digraph = 0.5
    static let transposition = 0.5
    /// A missing space ("alot" -> "a lot").
    static let wordSplit = 1.0
    /// A hyphen the candidate adds; Hunspell proposes splits like "ab-sail".
    static let hyphenSplit = 1.5
    /// English spelling follows sound loosely, so vowels get swapped, added or dropped ("seperate", "existance").
    static let englishVowel = 0.75
    static let englishVowelIndel = 0.75

    /// The costs above as values, so the benchmark can tune them.
    struct Costs: Sendable {
        var wrongAccent = ErrorModel.wrongAccent
        var iy = ErrorModel.iy
        var layoutSwap = ErrorModel.layoutSwap
        var nearbyKey = ErrorModel.nearbyKey
        var doubledLetter = ErrorModel.doubledLetter
        var digraph = ErrorModel.digraph
        var transposition = ErrorModel.transposition
        var wordSplit = ErrorModel.wordSplit
        var hyphenSplit = ErrorModel.hyphenSplit
        var englishVowel = ErrorModel.englishVowel
        var englishVowelIndel = ErrorModel.englishVowelIndel
    }

    private struct Letter {
        let character: Character
        let base: Character
        var isAccented: Bool { character != base }
    }

    static func cost(typed: String, candidate: String, language: Language? = nil, costs: Costs = Costs()) -> Double {
        let a = letters(typed)
        let b = letters(candidate)
        var costs = costs
        if language != .english {
            costs.englishVowel = 1
            costs.englishVowelIndel = 1
        }
        // Optimal string alignment over three rolling rows, as in EditDistance.
        var twoRowsBack = [Double](repeating: 0, count: b.count + 1)
        var previousRow = [Double](repeating: 0, count: b.count + 1)
        var currentRow = [Double](repeating: 0, count: b.count + 1)
        for j in b.indices { previousRow[j + 1] = previousRow[j] + missingCost(b, j, costs) }
        for i in a.indices {
            currentRow[0] = previousRow[0] + extraCost(a, i, costs)
            for j in b.indices {
                var value = min(
                    previousRow[j + 1] + extraCost(a, i, costs),
                    currentRow[j] + missingCost(b, j, costs),
                    previousRow[j] + substitutionCost(a[i], b[j], costs)
                )
                if i > 0, j > 0, a[i].base == b[j - 1].base, a[i - 1].base == b[j].base, a[i].base != a[i - 1].base {
                    value = min(value, twoRowsBack[j - 1] + costs.transposition)
                }
                currentRow[j + 1] = value
            }
            (twoRowsBack, previousRow, currentRow) = (previousRow, currentRow, twoRowsBack)
        }
        return previousRow[b.count]
    }

    private static func letters(_ word: String) -> [Letter] {
        word.lowercased().precomposedStringWithCanonicalMapping.map { character in
            Letter(character: character, base: EditDistance.fold(String(character)).first ?? character)
        }
    }

    private static func substitutionCost(_ typed: Letter, _ candidate: Letter, _ costs: Costs) -> Double {
        if typed.base == candidate.base {
            return typed.isAccented && typed.character != candidate.character ? costs.wrongAccent : 0
        }
        let accentDropped = typed.isAccented && !candidate.isAccented ? costs.wrongAccent : 0
        switch (typed.base, candidate.base) {
        case ("i", "y"), ("y", "i"): return costs.iy + accentDropped
        case ("y", "z"), ("z", "y"): return costs.layoutSwap + accentDropped
        default:
            let nearby = areNeighbors(typed.base, candidate.base) ? costs.nearbyKey : 1
            return isVowel(typed.base) && isVowel(candidate.base) ? min(costs.englishVowel, nearby) : nearby
        }
    }

    /// A typed letter the candidate does not have.
    private static func extraCost(_ typed: [Letter], _ index: Int, _ costs: Costs) -> Double {
        let letter = typed[index].base
        let adjacent = [index - 1, index + 1].filter(typed.indices.contains).map { typed[$0].base }
        if adjacent.contains(letter) { return costs.doubledLetter }
        let nearby = adjacent.contains { areNeighbors(letter, $0) } ? costs.nearbyKey : 1
        return isVowel(letter) ? min(costs.englishVowelIndel, nearby) : nearby
    }

    /// A letter of the candidate that was not typed.
    private static func missingCost(_ candidate: [Letter], _ index: Int, _ costs: Costs) -> Double {
        let letter = candidate[index].base
        if letter == " " { return costs.wordSplit }
        if letter == "-" { return costs.hyphenSplit }
        let adjacent = [index - 1, index + 1].filter(candidate.indices.contains).map { candidate[$0].base }
        if adjacent.contains(letter) { return costs.doubledLetter }
        if letter == "h" && index > 0 && candidate[index - 1].base == "c" { return costs.digraph }
        return isVowel(letter) ? costs.englishVowelIndel : 1
    }

    private static func isVowel(_ letter: Character) -> Bool {
        "aeiou".contains(letter)
    }

    private static func areNeighbors(_ first: Character, _ second: Character) -> Bool {
        neighbors[first]?.contains(second) == true
    }

    /// Adjacent keys on the Czech QWERTZ and the US QWERTY layout.
    private static let neighbors: [Character: Set<Character>] = {
        var neighbors: [Character: Set<Character>] = [:]
        for layout in [["qwertzuiop", "asdfghjkl", "yxcvbnm"], ["qwertyuiop", "asdfghjkl", "zxcvbnm"]] {
            let rows = layout.map(Array.init)
            for (row, keys) in rows.enumerated() {
                for (column, key) in keys.enumerated() {
                    // Each row sits about half a key right of the one above.
                    var near = [(row, column + 1)]
                    if row + 1 < rows.count { near += [(row + 1, column - 1), (row + 1, column)] }
                    for (nearRow, nearColumn) in near where rows[nearRow].indices.contains(nearColumn) {
                        let other = rows[nearRow][nearColumn]
                        neighbors[key, default: []].insert(other)
                        neighbors[other, default: []].insert(key)
                    }
                }
            }
        }
        return neighbors
    }()
}
