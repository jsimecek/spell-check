import Foundation
import Testing
@testable import SpellCore

/// Uses /bin/sh stand-ins for the real Apple helper process.
@Suite struct NativeGuessClientTests {
    private func client(_ script: String) -> NativeGuessClient {
        NativeGuessClient(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script])
    }

    private static let echoHelper = #"""
    while IFS= read -r line; do
      word=$(printf '%s' "$line" | sed -E 's/.*"word":"([^"]*)".*/\1/')
      printf '{"word":"%s","czech":["%s-cs"],"english":["%s-en"]}\n' "$word" "$word" "$word"
    done
    """#

    private func waitForCache(_ c: NativeGuessClient, _ word: String) -> NativeGuesses? {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if let cached = c.cachedGuesses(for: word) { return cached }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return nil
    }

    @Test func prefetchedAnswersLandInCache() {
        let c = client(Self.echoHelper)
        #expect(c.cachedGuesses(for: "praci") == nil)
        c.prefetch(["praci", "zitra"])
        #expect(waitForCache(c, "praci") == NativeGuesses(czech: ["praci-cs"], english: ["praci-en"]))
        #expect(waitForCache(c, "zitra")?.czech == ["zitra-cs"])
    }

    @Test func prefetchNeverBlocksOnSilentHelper() {
        let c = client("cat > /dev/null")
        let start = Date()
        c.prefetch((0..<20).map { "word\($0)" })
        #expect(Date().timeIntervalSince(start) < 0.1)
        #expect(c.cachedGuesses(for: "word0") == nil)
    }

    @Test func prefetchNeverBlocksOnOverlongWords() {
        let c = client("sleep 5")  // never reads stdin, so a full pipe would block the write
        let start = Date()
        c.prefetch((0..<NativeGuessClient.maxPendingWords).map { String(repeating: "a", count: 2000) + "\($0)" })
        #expect(Date().timeIntervalSince(start) < 0.1)
    }

    @Test func restartsHelperThatExited() {
        // Answers one request, then exits.
        let c = client(#"""
        read -r line
        word=$(printf '%s' "$line" | sed -E 's/.*"word":"([^"]*)".*/\1/')
        printf '{"word":"%s","czech":["a"],"english":[]}\n' "$word"
        """#)
        c.prefetch(["first"])
        #expect(waitForCache(c, "first")?.czech == ["a"])
        Thread.sleep(forTimeInterval: 0.2)
        c.prefetch(["second"])  // dead helper: may only surface as a failed write, never SIGPIPE
        c.prefetch(["second"])
        #expect(waitForCache(c, "second")?.czech == ["a"])
    }

    @Test func restartsHelperThatDiedWithFullQueue() throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("czen-helper-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: marker) }
        // First run dies without answering; later runs echo.
        let c = client("""
        if [ ! -e '\(marker.path)' ]; then touch '\(marker.path)'; read -r line; exit 0; fi
        \(Self.echoHelper)
        """)
        c.prefetch((0..<NativeGuessClient.maxPendingWords).map { "word\($0)" })
        Thread.sleep(forTimeInterval: 0.2)
        c.prefetch(["new"])  // dead helper: may only surface as a failed write
        c.prefetch(["new"])
        #expect(waitForCache(c, "new")?.czech == ["new-cs"])
    }

    @Test func retriesWordThatWasPendingWhenHelperDied() throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("czen-helper-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: marker) }
        // First run dies without answering; later runs echo.
        let c = client("""
        if [ ! -e '\(marker.path)' ]; then touch '\(marker.path)'; read -r line; exit 0; fi
        \(Self.echoHelper)
        """)
        c.prefetch(["word"])
        Thread.sleep(forTimeInterval: 0.2)
        c.prefetch(["word"])  // dead helper: may only surface as a failed write
        c.prefetch(["word"])
        #expect(waitForCache(c, "word")?.czech == ["word-cs"])
    }
}
