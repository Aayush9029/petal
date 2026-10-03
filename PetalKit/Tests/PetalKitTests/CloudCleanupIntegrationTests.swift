import AppKit
import Foundation
import Shared
import Testing
@testable import CloudCleanupClient

@Suite(.enabled(if: ProcessInfo.processInfo.environment["PETAL_CLOUD_TESTS"] == "1"))
struct CloudCleanupIntegrationTests {
    struct Target: CustomTestStringConvertible, Sendable {
        var provider: CloudProvider
        var model: CloudModel.ID
        var testDescription: String { "\(provider.displayName) \(model)" }

        var apiKey: String? {
            let name = switch provider {
            case .openAI: "OPENAI_API_KEY"
            case .anthropic: "ANTHROPIC_API_KEY"
            case .openRouter: "OPENROUTER_API_KEY"
            case .custom: "PETAL_CUSTOM_API_KEY"
            }
            return ProcessInfo.processInfo.environment[name]
        }

        func configuration(_ preset: CloudPromptPreset = .cleanUp, tools: Set<CloudTool> = []) throws -> CloudCleanupConfiguration {
            let key = try #require(apiKey, "No API key for \(provider.displayName)")
            return CloudCleanupConfiguration(
                connection: CloudConnection(provider: provider, apiKey: key),
                model: model,
                systemPrompt: preset.prompt,
                tools: tools
            )
        }
    }

    static let targets = [
        Target(provider: .openAI, model: "gpt-6-luna"),
        Target(provider: .anthropic, model: "claude-opus-5-5"),
        Target(provider: .anthropic, model: "claude-haiku-4-5"),
        Target(provider: .openRouter, model: "openai/gpt-6-luna"),
        Target(provider: .openRouter, model: "anthropic/claude-sonnet-5.5"),
    ].filter { $0.apiKey != nil }

    let runtime = CloudCleanupRuntime(
        send: { try await URLSession.shared.data(for: $0) },
        context: CloudRuntimeContext(clipboardText: { "The launch moved to Tuesday at 10 AM." })
    )

    @Test(arguments: targets)
    func cleansFillersAndCorrections(target: Target) async throws {
        let result = try await runtime.clean(
            "so um i need to like send the the report by uh friday no wait make that thursday",
            configuration: target.configuration()
        )
        #expect(result.text.contains("Thursday"), "\(result.text)")
        #expect(!result.text.contains("Friday"), "\(result.text)")
        #expect(!result.text.lowercased().contains(" um "), "\(result.text)")
    }

    @Test(arguments: targets)
    func keepsQuestionsInsteadOfAnsweringThem(target: Target) async throws {
        let input = "can you like explain why the build keeps failing on ci"
        let result = try await runtime.clean(input, configuration: target.configuration())
        #expect(result.text.hasSuffix("?"), "\(result.text)")
        #expect(result.text.split(separator: " ").count <= input.split(separator: " ").count + 2, "\(result.text)")
    }

    @Test(arguments: targets)
    func assistantPresetAnswers(target: Target) async throws {
        let result = try await runtime.clean("what's fifteen percent of eighty", configuration: target.configuration(.assistant))
        #expect(result.text.contains("12") || result.text.lowercased().contains("twelve"), "\(result.text)")
    }

    @Test(arguments: targets)
    func dateToolResolvesRelativeDates(target: Target) async throws {
        let result = try await runtime.clean(
            "remind me to call mom next friday",
            configuration: target.configuration(tools: [.dateTime])
        )
        let months = DateFormatter().monthSymbols ?? []
        #expect(result.toolCalls.contains("get_current_date_time"), "\(result)")
        #expect(months.contains { result.text.contains($0) } || result.text.contains("/"), "\(result.text)")
    }

    @Test(arguments: targets)
    func webSearchFillsInAFact(target: Target) async throws {
        let result = try await runtime.clean(
            "tell sam who the current ceo of openai is, look it up",
            configuration: target.configuration(tools: [.webSearch])
        )
        #expect(result.text.contains("Altman"), "\(result.text)")
        #expect(!result.text.contains("]("), "\(result.text)")
    }

    @Test(arguments: targets)
    func verifiesTheKey(target: Target) async throws {
        try await runtime.verifyKey(target.configuration().connection)
    }

    @Test(arguments: targets)
    func listsModelsThatIncludeTheDefault(target: Target) async throws {
        let models = try await runtime.availableModels(target.configuration().connection)
        #expect(models[id: target.model] != nil, "\(target.model) missing from \(models.count) models")
    }

    @Test(arguments: targets)
    func clipboardToolReadsCopiedText(target: Target) async throws {
        let result = try await runtime.clean(
            "reply to what i copied and say that works for me",
            configuration: target.configuration(.assistant, tools: [.clipboard])
        )
        #expect(result.toolCalls.contains("get_clipboard_text"), "\(result)")
        #expect(result.text.contains("Tuesday") || result.text.lowercased().contains("works"), "\(result.text)")
    }

    @Test(arguments: targets)
    func screenshotSpellsANameFromTheScreen(target: Target) async throws {
        let screenshot = try Self.screenshot(showing: "To: Siobhán Ó Ceallaigh\nSubject: Launch review")
        let runtime = CloudCleanupRuntime(
            send: { try await URLSession.shared.data(for: $0) },
            context: CloudRuntimeContext(screenshot: { screenshot })
        )
        let result = try await runtime.clean(
            "hey shivawn o kelly can we move the launch review to monday",
            configuration: target.configuration(tools: [.screen])
        )
        #expect(result.text.contains("Siobhán"), "\(result.text)")
    }

    static func screenshot(showing text: String) throws -> Data {
        let size = NSSize(width: 900, height: 300)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            (text as NSString).draw(
                at: NSPoint(x: 40, y: 120),
                withAttributes: [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black]
            )
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        return try #require(NSBitmapImageRep(data: tiff)?.representation(using: .jpeg, properties: [.compressionFactor: 0.8]))
    }

    @Test(arguments: targets)
    func checksTheModel(target: Target) async throws {
        try await runtime.checkModel(target.configuration())
    }

    @Test(arguments: targets)
    func reportsAMissingModel(target: Target) async throws {
        var configuration = try target.configuration()
        configuration.model = "petal-missing-model"
        await #expect(throws: CloudCleanupError.self) {
            try await runtime.checkModel(configuration)
        }
    }

    @Test(arguments: targets)
    func rejectsAWrongKey(target: Target) async throws {
        var connection = try target.configuration().connection
        connection.apiKey = "sk-invalid-petal-test"
        await #expect {
            try await runtime.verifyKey(connection)
        } throws: { error in
            (error as? CloudCleanupError)?.isAuthenticationFailure == true
        }
    }
}
