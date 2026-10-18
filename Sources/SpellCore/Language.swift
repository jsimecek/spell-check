/// The raw value is the ISO 639-1 code, also used as the prefix of the data files.
public enum Language: String, CaseIterable, Sendable {
    case czech = "cs"
    case english = "en"

    /// Hunspell dictionary file name without extension.
    var dictionaryName: String {
        switch self {
        case .czech: "cs_CZ"
        case .english: "en_US"
        }
    }
}
