import Foundation

extension StringProtocol {
    /// "monday" -> "Monday"; the rest of the string is left as is.
    func uppercasingFirstLetter() -> String {
        prefix(1).uppercased() + dropFirst()
    }

    /// "Foo" -> "foo"; the rest of the string is left as is.
    func lowercasingFirstLetter() -> String {
        prefix(1).lowercased() + dropFirst()
    }
}

extension String {
    var hasDiacritics: Bool {
        folding(options: .diacriticInsensitive, locale: nil) != self
    }
}
