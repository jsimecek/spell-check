import Foundation

public protocol LanguageModelScoring {
    /// log P(word | left) + log P(right | word); higher is more likely.
    func contextScore(_ word: String, left: String?, right: String?) -> Double
}

public enum NGramModelError: Error {
    case corrupt
}

/// Unigram + bigram counts in one sorted table of 64-bit hashes, memory-mapped from disk.
/// Layout (little-endian): "CZNG", version UInt32, total tokens UInt64, entry count UInt64,
/// keys [UInt64] (sorted), counts [UInt32].
public final class NGramModel: LanguageModelScoring {
    static let magic: UInt32 = 0x474E_5A43  // "CZNG"
    static let version: UInt32 = 1
    static let headerSize = 24
    static let backoff = 0.4

    private let data: Data
    private let entryCount: Int
    public let totalTokens: UInt64

    public convenience init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .alwaysMapped))
    }

    public init(data: Data) throws {
        guard data.count >= Self.headerSize else { throw NGramModelError.corrupt }
        let header = data.withUnsafeBytes { raw in
            (raw.loadUnaligned(fromByteOffset: 0, as: UInt32.self), raw.loadUnaligned(fromByteOffset: 4, as: UInt32.self),
             raw.loadUnaligned(fromByteOffset: 8, as: UInt64.self), raw.loadUnaligned(fromByteOffset: 16, as: UInt64.self))
        }
        guard header.0 == Self.magic, header.1 == Self.version,
              data.count == Self.headerSize + Int(header.3) * 12 else { throw NGramModelError.corrupt }
        self.data = data
        totalTokens = header.2
        entryCount = Int(header.3)
    }

    /// FNV-1a 64 over UTF-8: stable across processes, unlike Swift's Hasher.
    static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in s.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01b3
        }
        return h
    }

    static func key(_ a: String, _ b: String) -> UInt64 { hash(a + "\u{1}" + b) }

    // Keys hash raw UTF-8 of the NFC corpus, so decomposed input must be composed first.
    public func count(_ word: String) -> UInt32 { lookup(Self.hash(word.precomposedStringWithCanonicalMapping)) }

    public func count(_ a: String, _ b: String) -> UInt32 {
        lookup(Self.key(a.precomposedStringWithCanonicalMapping, b.precomposedStringWithCanonicalMapping))
    }

    private func lookup(_ key: UInt64) -> UInt32 {
        data.withUnsafeBytes { raw in
            var low = 0
            var high = entryCount - 1
            while low <= high {
                let mid = (low + high) / 2
                let value = raw.loadUnaligned(fromByteOffset: Self.headerSize + mid * 8, as: UInt64.self)
                if value == key {
                    return raw.loadUnaligned(fromByteOffset: Self.headerSize + entryCount * 8 + mid * 4, as: UInt32.self)
                }
                if value < key { low = mid + 1 } else { high = mid - 1 }
            }
            return 0
        }
    }

    /// Stupid backoff: bigram relative frequency when seen, otherwise 0.4 × unigram probability.
    /// A phrase ("v práci") is scored word by word as a chain.
    public func contextScore(_ word: String, left: String?, right: String?) -> Double {
        let total = Double(max(totalTokens, 1))
        func unigram(_ w: String) -> Double { (Double(count(w)) + 0.1) / total }
        func conditional(_ w: String, after previous: String) -> Double {
            let pair = count(previous, w)
            guard pair > 0 else { return Self.backoff * unigram(w) }
            return Double(pair) / Double(max(count(previous), pair))
        }
        var previous = left
        var score = 0.0
        for part in word.split(separator: " ").map(String.init) + (right.map { [$0] } ?? []) {
            score += log(previous.map { conditional(part, after: $0) } ?? unigram(part))
            previous = part
        }
        return score
    }

    /// Sentences at least this long without a single accent are treated as typed without accents.
    static let minUnaccentedSentenceTokens = 4

    /// Builds a model from Leipzig-style lines ("id<TAB>sentence"; the id is optional).
    /// `skipUnaccentedSentences` keeps Czech typed without accents from teaching wrong pairs ("mam rad").
    public static func build(lines: some Sequence<String>, minCount: UInt32, skipUnaccentedSentences: Bool = false) -> Data {
        var counts: [UInt64: UInt32] = [:]
        var total: UInt64 = 0
        for line in lines {
            let text = line.firstIndex(of: "\t").map { String(line[line.index(after: $0)...]) } ?? line
            let tokens = NGramTokenizer.tokens(in: text)
            if skipUnaccentedSentences, tokens.count >= minUnaccentedSentenceTokens,
               text.folding(options: .diacriticInsensitive, locale: nil) == text { continue }
            for (index, token) in tokens.enumerated() {
                total += 1
                counts[hash(token.word), default: 0] += 1
                if index > 0, tokens[index - 1].sentence == token.sentence {
                    counts[key(tokens[index - 1].word, token.word), default: 0] += 1
                }
            }
        }
        let kept = counts.filter { $0.value >= minCount }.sorted { $0.key < $1.key }
        var out = Data(capacity: headerSize + kept.count * 12)
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { out.append(contentsOf: $0) } }
        append(magic)
        append(version)
        append(total)
        append(UInt64(kept.count))
        for entry in kept { append(entry.key) }
        for entry in kept { append(entry.value) }
        return out
    }
}
