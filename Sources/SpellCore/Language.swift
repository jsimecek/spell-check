public enum Language: String, CaseIterable, Sendable {
    case czech = "cs"
    case english = "en"

    var dictionaryName: String {
        switch self {
        case .czech: "cs_CZ"
        case .english: "en_US"
        }
    }
}
