import Foundation
import Shared

struct AnthropicMessagesAPI: CloudChatAPI {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let version = "2023-06-01"
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    static let fallbackModels: Set<CloudModel.ID> = ["claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"]

    var configuration: CloudCleanupConfiguration
    var system: String
    var transcript: String
    var screenshot: Data?
    var messages: [JSONValue]
    var usesFallbacks = true

    init(configuration: CloudCleanupConfiguration, system: String, transcript: String, screenshot: Data? = nil) {
        self.configuration = configuration
        self.system = system
        self.transcript = transcript
        self.screenshot = screenshot
        messages = [Self.userMessage(transcript, screenshot: screenshot)]
    }

    static func userMessage(_ transcript: String, screenshot: Data?) -> JSONValue {
        let text = CloudCleanupPrompt.user(transcript)
        guard let screenshot else { return ["role": "user", "content": .string(text)] }
        return [
            "role": "user",
            "content": [
                [
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": .string(CloudCleanupPrompt.screenshotMediaType),
                        "data": .string(screenshot.base64EncodedString()),
                    ],
                ],
                ["type": "text", "text": .string(text)],
            ],
        ]
    }

    static func isCurrentGeneration(_ model: CloudModel.ID) -> Bool {
        guard let match = model.rawValue.lowercased().firstMatch(of: /^claude-(opus|sonnet|haiku|fable|mythos)-(\d+)(?:-(\d{1,2}))?(?:-|$)/) else {
            return false
        }
        let family = match.output.1
        guard let major = Int(match.output.2) else { return false }
        let minor = match.output.3.flatMap { Int($0) } ?? 0
        if family == "fable" || family == "mythos" { return true }
        if family == "haiku" { return false }
        return major >= 5 || (major == 4 && minor >= 6)
    }

    var tools: [JSONValue] {
        var tools: [JSONValue] = CloudCleanupPrompt.functionTools(for: configuration.tools).map { tool in
            [
                "name": .string(tool.name),
                "description": .string(tool.description),
                "input_schema": CloudCleanupPrompt.emptyParameters,
                "strict": true,
            ]
        }
        if configuration.tools.contains(.webSearch) {
            let type = Self.isCurrentGeneration(configuration.model) ? "web_search_20260209" : "web_search_20250305"
            tools.append(["type": .string(type), "name": "web_search", "max_uses": 3])
        }
        return tools
    }

    func request() throws -> URLRequest {
        try configuration.connection.requireAPIKey()
        var headers = [
            "x-api-key": configuration.connection.apiKey,
            "anthropic-version": Self.version,
        ]
        var body: [String: JSONValue] = [
            "model": .string(configuration.model.rawValue),
            "max_tokens": 16000,
            "system": .string(system),
            "messages": .array(messages),
        ]
        if Self.isCurrentGeneration(configuration.model) {
            body["output_config"] = ["effort": "low"]
        }
        if usesFallbacks, Self.fallbackModels.contains(configuration.model) {
            body["fallbacks"] = "default"
            headers["anthropic-beta"] = Self.fallbackBeta
        }
        if !tools.isEmpty {
            body["tools"] = .array(tools)
        }
        return try CloudHTTP.request(
            Self.endpoint,
            headers: headers,
            body: .object(body),
            timeout: CloudHTTP.timeout(for: configuration.tools)
        )
    }

    mutating func receive(_ response: JSONValue) throws -> CloudTurn {
        if response["type"]?.stringValue == "error" {
            throw CloudCleanupError.provider(response["error"]?["message"]?.stringValue ?? "Anthropic returned an error.")
        }
        let stopReason = response["stop_reason"]?.stringValue
        if stopReason == "refusal" {
            throw CloudCleanupError.refused
        }
        let content = response["content"]?.arrayValue ?? []
        messages.append(["role": "assistant", "content": .array(content)])

        switch stopReason {
        case "pause_turn":
            return .paused
        case "tool_use":
            let calls = content.compactMap { block -> CloudToolCall? in
                guard block["type"]?.stringValue == "tool_use",
                      let id = block["id"]?.stringValue,
                      let name = block["name"]?.stringValue
                else { return nil }
                return CloudToolCall(id: CloudToolCall.ID(rawValue: id), name: name, arguments: (block["input"] ?? [:]).encodedString())
            }
            if !calls.isEmpty {
                return .toolCalls(calls)
            }
        default:
            break
        }
        return .finished(text: Self.finalText(content), model: response["model"]?.stringValue.map { CloudModel.ID(rawValue: $0) })
    }

    static func finalText(_ content: [JSONValue]) -> String {
        let textTypes: Set<String> = ["text", "thinking", "redacted_thinking"]
        let boundary = content.lastIndex { !textTypes.contains($0["type"]?.stringValue ?? "") }
        let answer = boundary.map { content[content.index(after: $0)...] } ?? content[...]
        return answer
            .filter { $0["type"]?.stringValue == "text" }
            .compactMap { $0["text"]?.stringValue }
            .joined()
    }

    /// Server-side fallback is a beta, and some models cannot read images, so a request that the API rejects for either goes again without it.
    mutating func adapt(to error: CloudCleanupError) -> Bool {
        if usesFallbacks, case let .http(400, message) = error, message?.localizedCaseInsensitiveContains("fallback") == true {
            usesFallbacks = false
            return true
        }
        guard screenshot != nil, error.rejectsImages else { return false }
        screenshot = nil
        messages[0] = Self.userMessage(transcript, screenshot: nil)
        return true
    }

    mutating func appendToolResults(_ results: [CloudToolResult]) {
        messages.append([
            "role": "user",
            "content": .array(results.map { result in
                ["type": "tool_result", "tool_use_id": .string(result.call.id.rawValue), "content": .string(result.output)]
            }),
        ])
    }
}
