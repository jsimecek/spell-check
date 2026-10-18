/// Maps common spoken-Czech forms to standard ones ("kterej" -> "který", "vokno" -> "okno").
/// Results are unverified; callers keep only what the dictionary accepts.
enum ColloquialCzech {
    private static let suffixes: [(String, String)] = [
        ("ejch", "ých"), ("ejm", "ým"), ("ejma", "ýma"), ("ej", "ý"),
    ]

    static func standardForms(of word: String) -> [String] {
        var forms: [String] = []
        let lowered = word.lowercased()
        for (colloquial, standard) in suffixes where lowered.hasSuffix(colloquial) && word.count > colloquial.count + 1 {
            forms.append(String(word.dropLast(colloquial.count)) + standard)
        }
        if lowered.hasPrefix("vo"), word.count > 3, let first = word.first {
            let rest = word.dropFirst()
            forms.append(first.isUppercase ? rest.prefix(1).uppercased() + rest.dropFirst() : String(rest))
        }
        return forms
    }
}
