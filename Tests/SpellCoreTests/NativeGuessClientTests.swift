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
}
