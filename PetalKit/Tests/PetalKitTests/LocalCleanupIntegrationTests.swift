import Foundation
import MLX
import MLXLMCommon
@testable import LocalCleanupClient
import Shared
import Testing

/// Runs the real MLX weights. Set `PETAL_S1_MINI_DIR` to a local copy of Aayush9029/s1-mini-mlx-8bit.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PETAL_S1_MINI_DIR"] != nil), .serialized)
struct LocalCleanupIntegrationTests {
    let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PETAL_S1_MINI_DIR"] ?? "/")
    static let runtime = LocalCleanupRuntime()

    @Test
    func handBuiltPromptTokenizesLikeTheChatTemplate() async throws {
        let container = try await Self.runtime.prepare(directory: directory)
        let matches = try await container.perform { context in
            let manual = context.tokenizer.encode(
                text: LocalCleanupPrompt.text(model: .s1Mini, transcript: "so um send it by friday", controls: S1MiniControls()),
                addSpecialTokens: false
            )
            let templated = try context.tokenizer.applyChatTemplate(
                messages: [
                    ["role": "system", "content": S1MiniControls.defaultSystemPrompt],
                    ["role": "user", "content": "\(S1MiniControls().controlLine)\nso um send it by friday"],
                ],
                tools: nil,
                additionalContext: ["enable_thinking": false]
            )
            return manual == templated
        }
        #expect(matches)
    }

    /// Expected strings are the Python mlx-lm greedy outputs for the same 8-bit weights.
    @Test(arguments: [
        ("so um i need to like send the the report by uh friday no wait make that thursday", "So I need to send the report by Thursday."),
        ("i think the answer is forty two no sorry forty three", "I think the answer is 43."),
        ("let's meet at half past two tomorrow uh actually make it three fifteen p m", "Let's meet at 3:15pm tomorrow."),
        ("send it to support at superwhisper dot com", "Send it to support@superwhisper.com."),
        ("um", ""),
    ])
    func matchesModelCardExamples(input: String, expected: String) async throws {
        let result = try await Self.runtime.clean(input, model: .s1Mini, controls: S1MiniControls(), directory: directory)
        #expect(result.text == expected)
    }

    @Test
    func promptLookupMatchesPlainGreedyDecoding() async throws {
        let inputs = [
            "so um i need to like send the the report by uh friday no wait make that thursday",
            "hey sarah just wanted to follow up on the proposal can you send the numbers by end of week thanks john",
            "yo so um open app underscore model dot py and uh refactor the python script to use pydantic",
            "the invoice came to twenty three thousand four hundred and fifty dollars and it's due on march third twenty twenty six",
            (1 ... 20).map { "so um item \($0) is that the team uh needs to review pull request \($0 * 7)" }.joined(separator: " "),
        ]
        let container = try await Self.runtime.prepare(directory: directory)
        let mismatches = try await container.perform(values: inputs) { context, inputs in
            let stopTokens = Set(["<|im_end|>", "<|endoftext|>"].compactMap(context.tokenizer.convertTokenToId))
            var mismatches: [String] = []
            for input in inputs {
                let prompt = context.tokenizer.encode(
                    text: LocalCleanupPrompt.text(model: .s1Mini, transcript: input, controls: S1MiniControls()),
                    addSpecialTokens: false
                )
                let maxTokens = LocalCleanupPrompt.maxOutputTokens(promptTokens: prompt.count)
                var iterator = try TokenIterator(
                    input: LMInput(tokens: MLXArray(prompt)),
                    model: context.model,
                    processor: nil,
                    sampler: ArgMaxSampler(),
                    maxTokens: maxTokens
                )
                var plain: [Int] = []
                while let token = iterator.next(), !stopTokens.contains(token) { plain.append(token) }
                let speculative = try PromptLookupDecoder(
                    model: context.model,
                    stopTokens: stopTokens,
                    speculationMinPromptTokens: 0
                )
                .decode(prompt: prompt, maxTokens: maxTokens)
                print("S1MINI_LOOKUP tokens=\(plain.count) passes=\(speculative.forwardPasses)")
                if speculative.tokens != plain {
                    mismatches.append(context.tokenizer.decode(tokenIds: plain, skipSpecialTokens: true))
                }
            }
            return mismatches
        }
        #expect(mismatches.isEmpty)
    }

    @Test
    func controlsChangeOutput() async throws {
        let input = "hey sarah just wanted to follow up on the proposal can you send the numbers by end of week thanks john"
        let email = try await Self.runtime.clean(input, model: .s1Mini, controls: S1MiniControls(context: .email), directory: directory)
        #expect(email.text.hasPrefix("Hey Sarah,\n\n"))
        let list = try await Self.runtime.clean(
            "the three things i need are the updated deck the budget spreadsheet and the signed contract",
            model: .s1Mini,
            controls: S1MiniControls(structure: .lists),
            directory: directory
        )
        #expect(list.text.components(separatedBy: "\n- ").count == 4)
    }

    @Test
    func keepsVoiceAndTechnicalTerms() async throws {
        let result = try await Self.runtime.clean(
            "yo so um open app underscore model dot py and uh refactor the python script to use pydantic",
            model: .s1Mini,
            controls: S1MiniControls(),
            directory: directory
        )
        for term in ["Yo", "app_model.py", "Python", "Pydantic"] {
            #expect(result.text.contains(term), "\(term) missing from: \(result.text)")
        }
    }

    @Test
    func longTranscriptIsChunkedAndKeepsContent() async throws {
        let sentences = (1 ... 60).map { index in
            "so um item number \(index) on the list is that the team uh needs to review pull request \(index * 7) before the release on friday"
        }
        let result = try await Self.runtime.clean(sentences.joined(separator: " "), model: .s1Mini, controls: S1MiniControls(), directory: directory)
        print("S1MINI_LONG chunks=\(result.chunkCount) prompt=\(result.promptTokens) generated=\(result.generatedTokens) passes=\(result.forwardPasses) elapsed=\(result.elapsed)")
        #expect(result.chunkCount >= 2)
        #expect(result.text.contains("420"))
        #expect(!result.text.contains(" um "))
    }

    @Test
    func performance() async throws {
        let cold = ContinuousClock.now
        _ = try await LocalCleanupRuntime().prepare(directory: directory)
        let loadTime = ContinuousClock.now - cold

        let inputs = [
            "so um i need to like send the the report by uh friday no wait make that thursday",
            "the invoice came to twenty three thousand four hundred and fifty dollars and it's due on march third twenty twenty six",
            "hi team quick update the server migration finished last night at around eleven thirty pm we saw about two percent error rate for ten minutes which is back to normal now let me know if you see anything weird thanks alex",
            "okay so um i was thinking we could uh push the launch to next tuesday because the the qa build isn't ready yet",
        ]
        _ = try await Self.runtime.clean(inputs[0], model: .s1Mini, controls: S1MiniControls(), directory: directory)
        var latencies: [Duration] = []
        var generated = 0
        for _ in 0 ..< 3 {
            for input in inputs {
                let start = ContinuousClock.now
                let result = try await Self.runtime.clean(input, model: .s1Mini, controls: S1MiniControls(), directory: directory)
                latencies.append(ContinuousClock.now - start)
                generated += result.generatedTokens
            }
        }
        latencies.sort()
        let total = latencies.reduce(Duration.zero, +)
        let tokensPerSecond = Double(generated) / (Double(total.components.seconds) + Double(total.components.attoseconds) / 1e18)
        print("S1MINI_PERF load=\(loadTime) p50=\(latencies[latencies.count / 2]) max=\(latencies.last!) decodeIncludingPrefill=\(Int(tokensPerSecond)) tok/s")
        // Debug builds run MLX without optimization, so the limit applies only to Release.
        #if !DEBUG
        #expect(latencies[latencies.count / 2] < .milliseconds(600))
        #endif
    }
}
