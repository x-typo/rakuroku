import Foundation
import Testing
@testable import Rakuroku

@Suite("AnikotoTV resolver")
struct AnikotoTVResolverTests {
    @Test("Normalizes supported watch-path inputs")
    func normalizesWatchPaths() {
        let cases: [(input: String, expected: String?)] = [
            ("My-Anime", "/watch/my-anime"),
            (" /watch/My-Anime/ep-7?source=test#player ", "/watch/my-anime"),
            ("https://anikototv.to/watch/My-Anime/ep-4?source=test", "/watch/my-anime"),
            ("https://www.anikototv.to/watch/My-Anime", "/watch/my-anime"),
            ("prefix /watch/My-Anime/ep-2 suffix", "/watch/my-anime"),
        ]

        for testCase in cases {
            #expect(AnikotoTVResolver.normalizeWatchPathInput(testCase.input) == testCase.expected)
        }
    }

    @Test("Rejects empty, malformed, and foreign-host inputs")
    func rejectsUnsafeInputs() {
        let inputs = [
            "",
            "not a valid slug",
            "/watch/",
            "https://example.com/watch/my-anime",
            "https://anikototv.to.evil.example/watch/my-anime",
            "ftp://anikototv.to/watch/my-anime",
        ]

        for input in inputs {
            #expect(
                AnikotoTVResolver.normalizeWatchPathInput(input) == nil,
                "Unexpectedly accepted: \(input)"
            )
        }
    }

    @Test("Builds canonical episode URLs and clamps episode zero")
    func buildsEpisodeURLs() {
        #expect(
            AnikotoTVResolver.buildEpisodeURL(watchPath: "/watch/My-Anime", episode: 0)?.absoluteString
                == "https://anikototv.to/watch/my-anime/ep-1"
        )
        #expect(
            AnikotoTVResolver.buildEpisodeURL(watchPath: "my-anime", episode: 12)?.absoluteString
                == "https://anikototv.to/watch/my-anime/ep-12"
        )
    }
}
