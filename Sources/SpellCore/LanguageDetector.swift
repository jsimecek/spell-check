import NaturalLanguage

/// Czech or English, as judged by Apple's language recognizer.
enum LanguageDetector {
    static let minimumConfidence = 0.6
    static let strongConfidence = 0.9
    static let minimumLetters = 4

    static func detect(_ text: String) -> Language? {
        guard let best = hypothesis(text), best.confidence >= minimumConfidence else { return nil }
        return best.language
    }

    /// Restricting the recognizer to cs/en is what makes undiacritized Czech detectable.
    static func hypothesis(_ text: String) -> (language: Language, confidence: Double)? {
        guard text.unicodeScalars.filter(CharacterSet.letters.contains).count >= minimumLetters else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.czech, .english]
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
            let mapped = Language(rawValue: language.rawValue)
        else { return nil }
        return (mapped, confidence)
    }
}
