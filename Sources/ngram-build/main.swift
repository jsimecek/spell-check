import Foundation
import SpellCore

let usage = "usage: ngram-build <sentences.txt> <out.ngram> [minCount] [--skip-unaccented]"
let skipUnaccentedFlag = "--skip-unaccented"
let defaultMinCount: UInt32 = 2

let skipUnaccented = CommandLine.arguments.contains(skipUnaccentedFlag)
let arguments = CommandLine.arguments.filter { $0 != skipUnaccentedFlag }
func failWithUsage() -> Never {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}

guard arguments.count >= 3 else { failWithUsage() }
let inputPath = arguments[1]
let outputPath = arguments[2]
let minCount: UInt32
if arguments.count > 3 {
    guard let parsed = UInt32(arguments[3]) else { failWithUsage() }
    minCount = parsed
} else {
    minCount = defaultMinCount
}

let text = try String(contentsOfFile: inputPath, encoding: .utf8)
let data = NGramModel.build(
    lines: text.split(whereSeparator: \.isNewline).lazy.map(String.init),
    minCount: minCount,
    skipUnaccentedSentences: skipUnaccented
)
try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
print("Wrote \(outputPath) (\(data.count / 1_000_000) MB)")
