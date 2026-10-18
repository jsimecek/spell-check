import Foundation

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

    private let executable: URL
    private let arguments: [String]
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
        lock.lock()
        defer { lock.unlock() }
        return cache[word]
    }

    public func prefetch(_ words: [String]) {
        lock.lock()
        defer { lock.unlock() }
        let wanted = words.filter { cache[$0] == nil && !pending.contains($0) }
        // runningInput() first: restarting a dead helper is what clears a full `pending`.
        guard !wanted.isEmpty, let input = runningInput(), pending.count < Self.maxPendingWords else { return }
        var data = Data()
        for word in wanted.prefix(Self.maxPendingWords - pending.count) {
            guard let line = try? JSONEncoder().encode(NativeGuessRequest(word: word)) else { continue }
            data.append(line)
            data.append(UInt8(ascii: "\n"))
            pending.insert(word)
        }
        // Pipe writes this small do not block while the helper keeps reading.
        do { try input.write(contentsOf: data) } catch { stop() }
    }

    /// Caller holds `lock`.
    private func runningInput() -> FileHandle? {
        if let process, process.isRunning, let input { return input }
        pending.removeAll()
        let stdin = Pipe()
        let stdout = Pipe()
        let child = Process()
        child.executableURL = executable
        child.arguments = arguments
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = FileHandle.nullDevice
        // A dead helper must surface as a write error, not a SIGPIPE that kills us.
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        do { try child.run() } catch { return nil }
        process = child
        input = stdin.fileHandleForWriting
        Thread { [weak self] in self?.readAnswers(from: stdout.fileHandleForReading) }.start()
        return input
    }

    private func readAnswers(from output: FileHandle) {
        var buffer = Data()
        while true {
            let chunk = output.availableData
            if chunk.isEmpty { return }  // helper exited
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                guard let response = try? JSONDecoder().decode(NativeGuessResponse.self, from: line) else { continue }
                lock.lock()
                if cache.count >= Self.maxCachedWords { cache.removeAll() }
                cache[response.word] = NativeGuesses(czech: response.czech, english: response.english)
                pending.remove(response.word)
                lock.unlock()
            }
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
