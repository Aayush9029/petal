import DependenciesTestSupport
import Foundation
import LogClient
@testable import LocalCleanupClient
import Shared
import Testing

@Suite(
    .enabled(if: ProcessInfo.processInfo.environment["PETAL_W1_DIR"] != nil),
    .serialized,
    .dependency(\.logClient.debug, { @Sendable _, _ in })
)
struct PetalW1IntegrationTests {
    let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PETAL_W1_DIR"] ?? "/")
    static let runtime = LocalCleanupRuntime()

    private func clean(_ text: String) async throws -> String {
        try await Self.runtime.clean(text, directory: directory)
    }

    @Test
    func removesFillersAndResolvesCorrections() async throws {
        let result = try await clean("so um i need to like send the the report by uh friday no wait make that thursday")
        #expect(result.contains("Thursday"))
        #expect(!result.contains("Friday"))
        #expect(!result.lowercased().contains(" um "))
    }

    @Test(arguments: [
        "can you like explain why the build keeps failing on ci, like why does it fail, what's the reason it keeps failing",
        "what's the best way to structure a swiftui app with like observable models",
        "hey can you summarize this article for me real quick",
    ])
    func keepsQuestionsAndRequestsWithoutAnswering(input: String) async throws {
        let result = try await clean(input)
        #expect(result.split(separator: " ").count <= input.split(separator: " ").count + 3, "Looks like an answer: \(result)")
        #expect(result.contains("?") || result.lowercased().hasPrefix("hey"), "Lost the question: \(result)")
    }

    @Test
    func condensesRepeatedPoints() async throws {
        let input = "so the main thing is the paywall looks kind of ugly right now, like it's really not great, the paywall just doesn't look good, you know what i mean, we need to make the paywall look better, like way better, and it should use the full screen animations we already have"
        let result = try await clean(input)
        #expect(result.split(separator: " ").count < input.split(separator: " ").count * 3 / 4, "Not condensed: \(result)")
        #expect(result.lowercased().contains("animation"))
    }

    @Test
    func keepsTechnicalTerms() async throws {
        let result = try await clean("yo so um open app underscore model dot py and uh refactor the python script to use pydantic")
        for term in ["app_model.py", "Python"] {
            #expect(result.contains(term), "\(term) missing from: \(result)")
        }
    }

    @Test
    func performance() async throws {
        let inputs = [
            "so um i need to like send the the report by uh friday no wait make that thursday",
            "hi team quick update the server migration finished last night at around eleven thirty pm we saw about two percent error rate for ten minutes which is back to normal now let me know if you see anything weird thanks alex",
            "okay so um i was thinking we could uh push the launch to next tuesday because the the qa build isn't ready yet",
        ]
        _ = try await clean(inputs[0])
        var latencies: [Duration] = []
        for _ in 0 ..< 3 {
            for input in inputs {
                let start = ContinuousClock.now
                _ = try await clean(input)
                latencies.append(ContinuousClock.now - start)
            }
        }
        latencies.sort()
        print("PETAL_W1_PERF p50=\(latencies[latencies.count / 2]) max=\(latencies.last!)")
        // Debug builds run MLX without optimization, so the limit applies only to Release.
        #if !DEBUG
        #expect(latencies[latencies.count / 2] < .milliseconds(800))
        #endif
    }
}

@Test(
    .enabled(if: ProcessInfo.processInfo.environment["PETAL_TEST_W1_DOWNLOAD"] == "1"),
    .dependency(\.logClient.debug, { @Sendable _, _ in })
)
func petalW1DownloadsAndCleansThroughLiveClient() async throws {
    let client = LocalCleanupClient.liveValue
    if !client.isDownloaded() {
        try await client.download { _ in }
    }
    #expect(client.isDownloaded())
    let result = try await client.clean("um so like can you uh send me the deck by friday")
    #expect(result.contains("?"))
    #expect(!result.lowercased().contains("um"))
    await client.unload()
}
