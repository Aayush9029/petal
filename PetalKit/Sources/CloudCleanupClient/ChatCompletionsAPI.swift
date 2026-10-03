import Foundation
import Shared

struct ChatCompletionsAPI: CloudChatAPI {
    static let openRouterEndpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    var configuration: CloudCleanupConfiguration
    var messages: [JSONValue]

    init(configuration: CloudCleanupConfiguration, system: String, transcript: String) {
        self.configuration = configuration
        messages = [
            ["role": "system", "content": .string(system)],
            ["role": "user", "content": .string(CloudCleanupPrompt.user(transcript))],
        ]
    }

    var isOpenRouter: Bool { configuration.connection.provider == .openRouter }

    static func openRouterReasoning(for model: CloudModel.ID) -> JSONValue {
        let id = model.rawValue.lowercased()
        if id.hasPrefix("openai/gpt-6-luna") || id.hasPrefix("openai/gpt-6-sol") {
            return ["effort": "none"]
        }
        if id.hasPrefix("qwen/") || id.hasPrefix("deepseek/") {
            return ["enabled": false]
        }
        return ["effort": "low", "exclude": true]
    }

    var tools: [JSONValue] {
        var tools: [JSONValue] = CloudCleanupPrompt.functionTools(for: configuration.tools).map { tool in
            [
                "type": "function",
                "function": [
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "parameters": CloudCleanupPrompt.emptyParameters,
                ],
            ]
        }
        if isOpenRouter, configuration.tools.contains(.webSearch) {
            tools.append(["type": "openrouter:web_search", "parameters": ["max_results": 5]])
        }
        return tools
    }

    func endpoint() throws -> URL {
        isOpenRouter
            ? Self.openRouterEndpoint
            : try configuration.connection.customBaseURL().appending(path: "chat/completions")
    }

    func request() throws -> URLRequest {
        try configuration.connection.requireAPIKey()
        var body: [String: JSONValue] = [
            "model": .string(configuration.model.rawValue),
            "messages": .array(messages),
            "stream": false,
        ]
        var headers: [String: String] = [:]
        if !configuration.connection.apiKey.isEmpty {
            headers["Authorization"] = "Bearer \(configuration.connection.apiKey)"
        }
        if isOpenRouter {
            body["reasoning"] = Self.openRouterReasoning(for: configuration.model)
            headers["HTTP-Referer"] = CloudHTTP.referer
            headers["X-Title"] = "Petal"
        }
        if !tools.isEmpty {
            body["tools"] = .array(tools)
        }
        return try CloudHTTP.request(
            endpoint(),
            headers: headers,
            body: .object(body),
            timeout: CloudHTTP.timeout(for: configuration.tools)
        )
    }

    mutating func receive(_ response: JSONValue) throws -> CloudTurn {
        if let error = response["error"] {
            throw CloudCleanupError.provider(error["message"]?.stringValue ?? error.stringValue ?? "The provider returned an error.")
        }
        guard let message = response["choices"]?[0]?["message"] else {
            throw CloudCleanupError.invalidResponse
        }

        var assistant: [String: JSONValue] = ["role": "assistant", "content": message["content"] ?? .null]
        let toolCalls = message["tool_calls"]?.arrayValue ?? []
        if !toolCalls.isEmpty {
            assistant["tool_calls"] = .array(toolCalls)
        }
        if let details = message["reasoning_details"] {
            assistant["reasoning_details"] = details
        }
        messages.append(.object(assistant))

        let calls = toolCalls.compactMap { call -> CloudToolCall? in
            guard let id = call["id"]?.stringValue, let name = call["function"]?["name"]?.stringValue else { return nil }
            return CloudToolCall(id: CloudToolCall.ID(rawValue: id), name: name, arguments: call["function"]?["arguments"]?.stringValue ?? "{}")
        }
        if !calls.isEmpty {
            return .toolCalls(calls)
        }
        return .finished(text: Self.text(of: message["content"]), model: response["model"]?.stringValue.map { CloudModel.ID(rawValue: $0) })
    }

    static func text(of content: JSONValue?) -> String {
        if let text = content?.stringValue {
            return text
        }
        return (content?.arrayValue ?? [])
            .compactMap { $0["text"]?.stringValue }
            .joined()
    }

    mutating func appendToolResults(_ results: [CloudToolResult]) {
        messages += results.map { result in
            ["role": "tool", "tool_call_id": .string(result.call.id.rawValue), "content": .string(result.output)]
        }
    }
}
