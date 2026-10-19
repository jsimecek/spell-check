// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "CzEnSpell",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CzEnSpellServer", targets: ["CzEnSpellServer"]),
        .executable(name: "spellprobe", targets: ["spellprobe"]),
        .executable(name: "ngram-build", targets: ["ngram-build"]),
    ],
    targets: [
        .target(
            name: "CHunspell",
            exclude: ["COPYING", "COPYING.LESSER", "COPYING.MPL", "license.hunspell", "license.myspell", "VENDORED.md"],
            cxxSettings: [.define("HUNSPELL_STATIC"), .unsafeFlags(["-w"])]
        ),
        .target(name: "SpellCore", dependencies: ["CHunspell"]),
        .executableTarget(name: "CzEnSpellServer", dependencies: ["SpellCore"]),
        .executableTarget(name: "spellprobe"),
        .executableTarget(name: "ngram-build", dependencies: ["SpellCore"]),
        .testTarget(name: "SpellCoreTests", dependencies: ["SpellCore"], exclude: ["Benchmark"]),
    ],
    cxxLanguageStandard: .cxx17
)
