import AppKit
import SpellCore
import os

// The same binary doubles as the helper that asks Apple's checker for guesses.
if CommandLine.arguments.contains(AppleHelper.argument) { AppleHelper.run() }

let vendor = "CzEnSpell"
let log = Logger(subsystem: "io.github.jsimecek.CzEnSpell", category: "main")
let home = FileManager.default.homeDirectoryForCurrentUser

guard let dictionaries = Bundle.main.resourceURL?.appendingPathComponent("Dictionaries"),
    let services = Bundle.main.infoDictionary?["NSServices"] as? [[String: Any]],
    let languages = services.first?["NSLanguages"] as? [String],
    let languageID = languages.first
else {
    log.fault("Must run from inside CzEnSpell.service")
    exit(1)
}

let speller: BilingualSpeller
do {
    let learned = try LearnedWords(
        storeURL: home.appendingPathComponent("Library/Application Support/CzEnSpell/learned.txt"),
        readOnlySources: [home.appendingPathComponent("Library/Spelling/LocalDictionary")]
    )
    let nativeGuesses = Bundle.main.executableURL.map {
        NativeGuessClient(executable: $0, arguments: [AppleHelper.argument])
    }
    nativeGuesses?.prefetch(["warmup"])  // starts the helper before the first real request
    speller = try BilingualSpeller(dictionaryDirectory: dictionaries, learnedWords: learned, nativeGuesses: nativeGuesses)
} catch {
    log.fault("Startup failed: \(String(describing: error), privacy: .public)")
    exit(1)
}

let delegate = SpellServerDelegate(speller: speller, languageID: languageID)
nonisolated(unsafe) let server = NSSpellServer()
for language in languages where !server.registerLanguage(language, byVendor: vendor) {
    log.fault("Could not register \(language, privacy: .public)")
    exit(1)
}
server.delegate = delegate
log.notice("Serving \(languages, privacy: .public)")

// Callbacks still arrive on the main thread; NSApplication's loop is what lets
// LaunchServices see the APPL check in (without it, launches time out with errAETimeout).
Thread { server.run() }.start()
NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.run()
