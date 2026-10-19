import Foundation

protocol LanguageModelScoring {
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
    static let keySize = MemoryLayout<UInt64>.size
    static let countSize = MemoryLayout<UInt32>.size
    static let backoff = 0.4

    private let data: Data
    private let entryCount: Int
    let totalTokens: UInt64

    convenience init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .alwaysMapped))
    }

    init(data: Data) throws {
        guard data.count >= Self.headerSize else { throw NGramModelError.corrupt }
        let (magic, version, totalTokens, entryCount) = data.withUnsafeBytes { raw in
            (
                raw.loadLittleEndian(at: 0, as: UInt32.self),
                raw.loadLittleEndian(at: 4, as: UInt32.self),
                raw.loadLittleEndian(at: 8, as: UInt64.self),
                raw.loadLittleEndian(at: 16, as: UInt64.self)
            )
        }
        let payloadSize = data.count - Self.headerSize
        let entrySize = Self.keySize + Self.countSize
        guard magic == Self.magic, version == Self.version, payloadSize % entrySize == 0,
            entryCount == UInt64(payloadSize / entrySize)
        else { throw NGramModelError.corrupt }
        self.data = data
        self.totalTokens = totalTokens
        self.entryCount = Int(entryCount)
    }

    /// FNV-1a 64 over UTF-8: stable across processes, unlike Swift's Hasher.
    static func hash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    static func bigramKey(_ first: String, _ second: String) -> UInt64 {
        hash(first + "\u{1}" + second)
    }

    // Keys hash raw UTF-8 of the NFC corpus, so decomposed input must be composed first.
    func count(_ word: String) -> UInt32 {
        lookup(Self.hash(word.precomposedStringWithCanonicalMapping))
    }

    func count(_ first: String, _ second: String) -> UInt32 {
        lookup(Self.bigramKey(first.precomposedStringWithCanonicalMapping, second.precomposedStringWithCanonicalMapping))
    }

    /// Binary search over the sorted keys; 0 when the key is absent.
    private func lookup(_ key: UInt64) -> UInt32 {
        let keysOffset = Self.headerSize
        let countsOffset = keysOffset + entryCount * Self.keySize
        return data.withUnsafeBytes { raw in
            var low = 0
            var high = entryCount - 1
            while low <= high {
                let middle = (low + high) / 2
                let middleKey = raw.loadLittleEndian(at: keysOffset + middle * Self.keySize, as: UInt64.self)
                if middleKey == key {
                    return raw.loadLittleEndian(at: countsOffset + middle * Self.countSize, as: UInt32.self)
                }
                if middleKey < key { low = middle + 1 } else { high = middle - 1 }
            }
            return 0
        }
    }

    /// Stupid backoff: bigram relative frequency when seen, otherwise 0.4 × unigram probability.
    /// A phrase ("v práci") is scored word by word as a chain.
    func contextScore(_ word: String, left: String?, right: String?) -> Double {
        let total = Double(max(totalTokens, 1))
        func unigram(_ word: String) -> Double {
            (Double(count(word)) + 0.1) / total
        }
        func conditional(_ word: String, after previous: String) -> Double {
            let pairCount = count(previous, word)
            guard pairCount > 0 else { return Self.backoff * unigram(word) }
            return Double(pairCount) / Double(max(count(previous), pairCount))
        }
        var chain = word.split(separator: " ").map(String.init)
        if let right { chain.append(right) }
        var previous = left
        var score = 0.0
        for current in chain {
            let probability = if let previous { conditional(current, after: previous) } else { unigram(current) }
            score += log(probability)
            previous = current
        }
        return score
    }
}

// MARK: - Building

extension NGramModel {
    /// Sentences at least this long without a single accent are treated as typed without accents.
    static let minUnaccentedSentenceTokens = 4

    /// Builds a model from Leipzig-style lines ("id<TAB>sentence"; the id is optional).
    /// `skipUnaccentedSentences` keeps Czech typed without accents from teaching wrong pairs ("mam rad").
    public static func build(lines: some Sequence<String>, minCount: UInt32, skipUnaccentedSentences: Bool = false) -> Data {
        var counts: [UInt64: UInt32] = [:]
        var totalTokens: UInt64 = 0
        for line in lines {
            let text = line.firstIndex(of: "\t").map { String(line[line.index(after: $0)...]) } ?? line
            let tokens = NGramTokenizer.tokens(in: text)
            if skipUnaccentedSentences, tokens.count >= minUnaccentedSentenceTokens, !text.hasDiacritics { continue }
            for (index, token) in tokens.enumerated() {
                totalTokens += 1
                counts[hash(token.word), default: 0] += 1
                if index > 0, tokens[index - 1].sentence == token.sentence {
                    counts[bigramKey(tokens[index - 1].word, token.word), default: 0] += 1
                }
            }
        }
        let kept = counts.filter { $0.value >= minCount }.sorted { $0.key < $1.key }

        var output = Data(capacity: headerSize + kept.count * (keySize + countSize))
        func append(_ value: some FixedWidthInteger) {
            withUnsafeBytes(of: value.littleEndian) { output.append(contentsOf: $0) }
        }
        append(magic)
        append(version)
        append(totalTokens)
        append(UInt64(kept.count))
        for entry in kept { append(entry.key) }
        for entry in kept { append(entry.value) }
        return output
    }
}

private extension UnsafeRawBufferPointer {
    func loadLittleEndian<T: FixedWidthInteger & BitwiseCopyable>(at offset: Int, as type: T.Type) -> T {
        T(littleEndian: loadUnaligned(fromByteOffset: offset, as: T.self))
    }
}
