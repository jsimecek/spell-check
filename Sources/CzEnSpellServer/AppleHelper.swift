import AppKit
import SpellCore

/// `CzEnSpell --apple-helper`: answers guess requests with Apple's own cs/en dictionaries.
/// Runs as a child of the spell server because NSSpellChecker stalls inside spell server callbacks.
/// Requests are answered one at a time; each one takes ~10 ms while the spell server is idle.
enum AppleHelper {
    static let argument = "--apple-helper"

    static func run() -> Never {
        Thread {
            while let line = readLine(strippingNewline: true) {
                guard let request = try? JSONDecoder().decode(NativeGuessRequest.self, from: Data(line.utf8)) else { continue }
                let response = DispatchQueue.main.sync {
                    NativeGuessResponse(
                        word: request.word,
                        czech: guesses(for: request.word, language: "cs"),
                        english: guesses(for: request.word, language: "en")
                    )
                }
                guard var data = try? JSONEncoder().encode(response) else { continue }
                data.append(UInt8(ascii: "\n"))
                FileHandle.standardOutput.write(data)
            }
            exit(0)  // the server closed the pipe
        }.start()
        // A real main run loop: dispatchMain would run main-queue work off the main thread.
        RunLoop.main.add(Port(), forMode: .default)
        while true { RunLoop.main.run(mode: .default, before: .distantFuture) }
    }

    private static func guesses(for word: String, language: String) -> [String] {
        let range = NSRange(location: 0, length: (word as NSString).length)
        return NSSpellChecker.shared.guesses(forWordRange: range, in: word, language: language, inSpellDocumentWithTag: 0) ?? []
    }
}
