import Foundation
import os
import Shared

private let logger = Logger(subsystem: "com.optimalapps.petal", category: "CloudCleanupClient")

struct CloudCleanupRuntime: Sendable {
    static let maxRequests = 6
    static let modelCheckSystemPrompt = "Reply with the word OK."

    var send: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    var context: CloudRuntimeContext

    func clean(_ transcript: String, configuration: CloudCleanupConfiguration) async throws -> CloudCleanupResult {
        let variables = CloudCleanupPrompt.variables(
            now: context.now(),
            timeZone: context.timeZone,
            locale: context.locale,
            appName: await context.appName(),
            userName: context.userName()
        )
        let system = CloudCleanupPrompt.system(configuration.systemPrompt, tools: configuration.tools, variables: variables)
        var api = Self.api(for: configuration, system: system, transcript: transcript)
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
                    results.append(CloudToolResult(call: call, output: await output(for: call)))
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
        for _ in 1 ... 2 {
            guard let response = try await nextResponse(&api, provider: check.connection.provider) else { continue }
            _ = try api.receive(response)
            return
        }
    }

    static func api(for configuration: CloudCleanupConfiguration, system: String, transcript: String) -> any CloudChatAPI {
        switch configuration.connection.provider {
        case .openAI: OpenAIResponsesAPI(configuration: configuration, system: system, transcript: transcript)
        case .anthropic: AnthropicMessagesAPI(configuration: configuration, system: system, transcript: transcript)
        case .openRouter, .custom: ChatCompletionsAPI(configuration: configuration, system: system, transcript: transcript)
        }
    }

    func output(for call: CloudToolCall) async -> String {
        switch call.name {
        case CloudTool.dateTime.functionName:
            CloudCleanupPrompt.dateTimeToolOutput(now: context.now(), timeZone: context.timeZone)
        case CloudTool.clipboard.functionName:
            CloudCleanupPrompt.textToolOutput(await context.clipboardText(), emptyMessage: "The clipboard has no text.")
        case CloudTool.selectedText.functionName:
            CloudCleanupPrompt.textToolOutput(await context.selectedText(), emptyMessage: "No text is selected.")
        default:
            (["error": .string("Unknown tool \(call.name).")] as JSONValue).encodedString()
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
