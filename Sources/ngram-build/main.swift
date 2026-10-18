import Foundation
import SpellCore

// Usage: ngram-build <sentences.txt> <out.ngram> [minCount] [--skip-unaccented]
let args = CommandLine.arguments.filter { $0 != "--skip-unaccented" }
let skipUnaccented = CommandLine.arguments.contains("--skip-unaccented")
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: ngram-build <sentences.txt> <out.ngram> [minCount] [--skip-unaccented]\n".data(using: .utf8)!)
    exit(2)
}
let minCount = args.count > 3 ? UInt32(args[3]) ?? 2 : 2
let text = try String(contentsOfFile: args[1], encoding: .utf8)
let data = NGramModel.build(
    lines: text.split(whereSeparator: \.isNewline).lazy.map(String.init),
    minCount: minCount, skipUnaccentedSentences: skipUnaccented
)
try data.write(to: URL(fileURLWithPath: args[2]), options: .atomic)
print("Wrote \(args[2]) (\(data.count / 1_000_000) MB)")
