import Foundation
import Testing

@testable import SpellCore

/// Uses /bin/sh stand-ins for the real Apple helper process.
@Suite struct NativeGuessClientTests {
    private func makeClient(_ script: String) -> NativeGuessClient {
        NativeGuessClient(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script])
    }

    private static let echoHelper = #"""
        while IFS= read -r line; do
          word=$(printf '%s' "$line" | sed -E 's/.*"word":"([^"]*)".*/\1/')
          printf '{"word":"%s","czech":["%s-cs"],"english":["%s-en"]}\n' "$word" "$word" "$word"
        done
        """#

    /// First run dies after reading one request without answering; later runs echo.
    private static func diesOnceThenEchoes(marker: URL) -> String {
        """
        if [ ! -e '\(marker.path)' ]; then touch '\(marker.path)'; read -r line; exit 0; fi
        \(echoHelper)
        """
    }

    private func waitForCache(_ client: NativeGuessClient, _ word: String) -> NativeGuesses? {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if let cached = client.cachedGuesses(for: word) { return cached }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return nil
    }

    @Test func prefetchedAnswersLandInCache() {
        let client = makeClient(Self.echoHelper)
        #expect(client.cachedGuesses(for: "praci") == nil)
        client.prefetch(["praci", "zitra"])
        #expect(waitForCache(client, "praci") == NativeGuesses(czech: ["praci-cs"], english: ["praci-en"]))
        #expect(waitForCache(client, "zitra")?.czech == ["zitra-cs"])
    }

    @Test func releasedWhileHelperRuns() {
        var client: NativeGuessClient? = makeClient(Self.echoHelper)
        weak let released = client
        client?.prefetch(["praci"])
        #expect(client.flatMap { waitForCache($0, "praci") } != nil)
        client = nil
        let deadline = Date().addingTimeInterval(2)
        while released != nil, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        #expect(released == nil)
    }

    @Test func prefetchNeverBlocksOnSilentHelper() {
        let client = makeClient("cat > /dev/null")
        let start = Date()
        client.prefetch((0..<20).map { "word\($0)" })
        #expect(Date().timeIntervalSince(start) < 0.1)
        #expect(client.cachedGuesses(for: "word0") == nil)
    }

    @Test func prefetchNeverBlocksOnOverlongWords() {
        let client = makeClient("sleep 5")  // never reads stdin, so a full pipe would block the write
        let start = Date()
        client.prefetch((0..<NativeGuessClient.maxPendingWords).map { String(repeating: "a", count: 2000) + "\($0)" })
        #expect(Date().timeIntervalSince(start) < 0.1)
    }

    @Test func skipsWordsWhoseRequestEncodesTooLong() {
        // JSON escapes control characters to six bytes, so a short word can still overfill the pipe.
        let client = makeClient(Self.echoHelper)
        let escaped = String(repeating: "\u{1}", count: NativeGuessClient.maxWordLength)
        client.prefetch([escaped, "ok"])
        #expect(waitForCache(client, "ok") != nil)
        #expect(client.cachedGuesses(for: escaped) == nil)
    }

    @Test func restartsHelperThatExited() {
        // Answers one request, then exits.
        let client = makeClient(
            #"""
            read -r line
            word=$(printf '%s' "$line" | sed -E 's/.*"word":"([^"]*)".*/\1/')
            printf '{"word":"%s","czech":["a"],"english":[]}\n' "$word"
            """#)
        client.prefetch(["first"])
        #expect(waitForCache(client, "first")?.czech == ["a"])
        Thread.sleep(forTimeInterval: 0.2)
        client.prefetch(["second"])  // dead helper: may only surface as a failed write, never SIGPIPE
        client.prefetch(["second"])
        #expect(waitForCache(client, "second")?.czech == ["a"])
    }

    @Test func restartsHelperThatDiedWithFullQueue() throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("czen-helper-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: marker) }
        let client = makeClient(Self.diesOnceThenEchoes(marker: marker))
        client.prefetch((0..<NativeGuessClient.maxPendingWords).map { "word\($0)" })
        Thread.sleep(forTimeInterval: 0.2)
        client.prefetch(["new"])  // dead helper: may only surface as a failed write
        client.prefetch(["new"])
        #expect(waitForCache(client, "new")?.czech == ["new-cs"])
    }

    @Test func retriesWordThatWasPendingWhenHelperDied() throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("czen-helper-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: marker) }
        let client = makeClient(Self.diesOnceThenEchoes(marker: marker))
        client.prefetch(["word"])
        Thread.sleep(forTimeInterval: 0.2)
        client.prefetch(["word"])  // dead helper: may only surface as a failed write
        client.prefetch(["word"])
        #expect(waitForCache(client, "word")?.czech == ["word-cs"])
    }
}
