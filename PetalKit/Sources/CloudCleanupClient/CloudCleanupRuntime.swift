import Foundation
import os
import Shared
import SystemContextClient

private let logger = Logger(subsystem: "com.optimalapps.petal", category: "CloudCleanupClient")

struct CloudCleanupRuntime: Sendable {
    static let maxRequests = 6
    static let modelCheckSystemPrompt = "Reply with the word OK."

    var send: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    func clean(_ transcript: String, configuration: CloudCleanupConfiguration) async throws -> CloudCleanupResult {
        @Dependency(\.systemContextClient) var context
        @Dependency(\.timeZone) var timeZone
        @Dependency(\.locale) var locale
        let screenshot = configuration.tools.contains(.screen) ? await context.screenshot() : nil
        let used = CloudCleanupPrompt.usedVariables(in: configuration.systemPrompt)
        let variables = CloudCleanupPrompt.variables(
            timeZone: timeZone,
            locale: locale,
            appName: used.contains(.app) ? await context.frontmostAppName() : nil,
            windowTitle: used.contains(.window) ? await context.frontmostWindowTitle() : nil,
            userName: used.contains(.name) || used.contains(.firstName) ? context.userFullName() : ""
        )
        let promptTools = screenshot == nil ? configuration.tools.subtracting([.screen]) : configuration.tools
        let system = CloudCleanupPrompt.system(configuration.systemPrompt, tools: promptTools, variables: variables)
        var api = Self.api(for: configuration, system: system, transcript: transcript, screenshot: screenshot)
        var toolCalls: [String] = []

        for requestNumber in 1 ... Self.maxRequests {
            guard let response = try await nextResponse(&api, provider: configuration.connection.provider) else { continue }
            switch try api.receive(response) {
            case let .finished(text, model):
                let cleaned = CloudOutputSanitizer.clean(text)
                guard !cleaned.isEmpty else { throw CloudCleanupError.emptyResponse }
                logger.info("Cloud cleanup finished: provider=\(configuration.connection.provider.rawValue, privacy: .public), model=\((model ?? configuration.model).rawValue, privacy: .public), requests=\(requestNumber), tools=\(toolCalls.joined(separator: ","), privacy: .public)")
                return CloudCleanupResult(text: cleaned, model: model, toolCalls: toolCalls, requestCount: requestNumber)
            case let .toolCalls(calls):
                toolCalls += calls.map(\.name)
                var results: [CloudToolResult] = []
                for call in calls {
                    results.append(CloudToolResult(call: call, output: await output(for: call, enabledTools: configuration.tools)))
                }
                api.appendToolResults(results)
            case .paused:
                continue
            }
        }
        throw CloudCleanupError.tooManyToolCalls
    }

    func verifyKey(_ connection: CloudConnection) async throws {
        _ = try await perform(CloudModelCatalog.keyCheckRequest(for: connection), provider: connection.provider)
    }

    func availableModels(_ connection: CloudConnection) async throws -> IdentifiedArrayOf<CloudModel> {
        let response = try await perform(CloudModelCatalog.listRequest(for: connection), provider: connection.provider)
        return CloudModelCatalog.models(from: response, provider: connection.provider)
    }

    func checkModel(_ configuration: CloudCleanupConfiguration) async throws {
        var check = configuration
        check.tools = []
        var api = Self.api(for: check, system: Self.modelCheckSystemPrompt, transcript: "OK")
        while true {
            if let response = try await nextResponse(&api, provider: check.connection.provider) {
                _ = try api.receive(response)
                return
            }
        }
    }

    static func api(
        for configuration: CloudCleanupConfiguration,
        system: String,
        transcript: String,
        screenshot: Data? = nil
    ) -> any CloudChatAPI {
        switch configuration.connection.provider {
        case .openAI: OpenAIResponsesAPI(configuration: configuration, system: system, transcript: transcript, screenshot: screenshot)
        case .anthropic: AnthropicMessagesAPI(configuration: configuration, system: system, transcript: transcript, screenshot: screenshot)
        case .openRouter, .custom: ChatCompletionsAPI(configuration: configuration, system: system, transcript: transcript, screenshot: screenshot)
        }
    }

    private func output(for call: CloudToolCall, enabledTools: Set<CloudTool>) async -> String {
        @Dependency(\.systemContextClient) var context
        switch enabledTools.first(where: { $0.functionName == call.name }) {
        case .dateTime:
            @Dependency(\.date.now) var now
            @Dependency(\.timeZone) var timeZone
            return CloudCleanupPrompt.dateTimeToolOutput(now: now, timeZone: timeZone)
        case .clipboard:
            return CloudCleanupPrompt.textToolOutput(await context.clipboardText(), emptyMessage: "The clipboard has no text.")
        case .selectedText:
            return CloudCleanupPrompt.textToolOutput(await context.selectedText(), emptyMessage: "No text is selected.")
        default:
            return (["error": .string("Unknown tool \(call.name).")] as JSONValue).encodedString()
        }
    }

    private func nextResponse(_ api: inout any CloudChatAPI, provider: CloudProvider) async throws -> JSONValue? {
        do {
            return try await perform(api.request(), provider: provider)
        } catch let error as CloudCleanupError {
            if api.adapt(to: error) { return nil }
            throw error
        }
    }

    private func perform(_ request: URLRequest, provider: CloudProvider) async throws -> JSONValue {
        let (data, response) = try await send(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else {
            logger.error("Cloud request failed: provider=\(provider.rawValue, privacy: .public), status=\(status)")
            throw CloudCleanupError.http(status: status, message: CloudHTTP.errorMessage(from: data))
        }
        do {
            return try JSONValue.decode(data)
        } catch {
            throw CloudCleanupError.invalidResponse
        }
    }
}
