import Foundation

/// Apple's own guesses for one word.
public struct NativeGuesses: Codable, Equatable, Sendable {
    public var czech: [String]
    public var english: [String]

    public init(czech: [String], english: [String]) {
        self.czech = czech
        self.english = english
    }
}

public protocol NativeGuessProviding: AnyObject {
    /// Never blocks: returns only what has already been fetched.
    func cachedGuesses(for word: String) -> NativeGuesses?
    /// Asks for guesses in the background.
    func prefetch(_ words: [String])
}

/// One JSON line per message between the spell server and its helper process.
public struct NativeGuessRequest: Codable, Sendable {
    public let word: String

    public init(word: String) { self.word = word }
}

public struct NativeGuessResponse: Codable, Sendable {
    public let word: String
    public let czech: [String]
    public let english: [String]

    public init(word: String, czech: [String], english: [String]) {
        self.word = word
        self.czech = czech
        self.english = english
    }
}

/// Talks to the helper over stdin/stdout without ever waiting for it. Waiting is not an option:
/// Apple's checker in the helper pings every spell server, including this busy one, so a
/// synchronous request from inside a spell server callback always stalls ~0.5 s.
public final class NativeGuessClient: NativeGuessProviding, @unchecked Sendable {
    static let maxCachedWords = 2000
    static let maxPendingWords = 100
    // No real cs/en word is longer.
    static let maxWordLength = 48
    // Keeps all in-flight requests under the 16 KB pipe buffer, so a stuck helper never blocks a write.
    static let maxRequestBytes = 16 * 1024 / maxPendingWords

    private let executable: URL
    private let arguments: [String]
    // Guards all mutable state below; answers arrive on a background reader thread.
    private let lock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var cache: [String: NativeGuesses] = [:]
    private var pending: Set<String> = []

    public init(executable: URL, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    deinit { process?.terminate() }

    public func cachedGuesses(for word: String) -> NativeGuesses? {
        lock.withLock { cache[word] }
    }

    public func prefetch(_ words: [String]) {
        lock.withLock {
            let wanted = words.filter { $0.utf16.count <= Self.maxWordLength && cache[$0] == nil }
            // runningInput() before checking `pending`: restarting a dead helper is what clears its stale entries.
            guard !wanted.isEmpty, let input = runningInput(), pending.count < Self.maxPendingWords else { return }
            var requests = Data()
            for word in wanted where pending.count < Self.maxPendingWords && !pending.contains(word) {
                guard let line = Self.requestLine(for: word) else { continue }
                requests.append(line)
                pending.insert(word)
            }
            do { try input.write(contentsOf: requests) } catch { stop() }
        }
    }

    /// The newline-terminated JSON request, or nil if it is too long to send.
    private static func requestLine(for word: String) -> Data? {
        guard var line = try? JSONEncoder().encode(NativeGuessRequest(word: word)), line.count < maxRequestBytes else {
            return nil
        }
        line.append(UInt8(ascii: "\n"))
        return line
    }

    /// The helper's stdin, starting a new helper if none is running. Caller holds `lock`.
    private func runningInput() -> FileHandle? {
        if let process, process.isRunning, let input { return input }
        pending.removeAll()
        let stdin = Pipe()
        let stdout = Pipe()
        let helper = Process()
        helper.executableURL = executable
        helper.arguments = arguments
        helper.standardInput = stdin
        helper.standardOutput = stdout
        helper.standardError = FileHandle.nullDevice
        // A dead helper must surface as a write error, not a SIGPIPE that kills us.
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        do { try helper.run() } catch { return nil }
        process = helper
        input = stdin.fileHandleForWriting
        // The reader holds self only weakly, so deinit can still terminate a running helper.
        let store: @Sendable (NativeGuessResponse) -> Void = { [weak self] in self?.store($0) }
        Thread { Self.readAnswers(from: stdout.fileHandleForReading, store: store) }.start()
        return input
    }

    /// Runs on its own thread until the helper exits.
    private static func readAnswers(from output: FileHandle, store: (NativeGuessResponse) -> Void) {
        var buffer = Data()
        while true {
            let chunk = output.availableData
            if chunk.isEmpty { return }  // helper exited
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                if let response = try? JSONDecoder().decode(NativeGuessResponse.self, from: line) {
                    store(response)
                }
            }
        }
    }

    private func store(_ response: NativeGuessResponse) {
        lock.withLock {
            if cache.count >= Self.maxCachedWords { cache.removeAll() }
            cache[response.word] = NativeGuesses(czech: response.czech, english: response.english)
            pending.remove(response.word)
        }
    }

    /// Caller holds `lock`.
    private func stop() {
        process?.terminate()
        process = nil
        input = nil
        pending.removeAll()
    }
}
