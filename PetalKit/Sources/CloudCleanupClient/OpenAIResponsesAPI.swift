import Foundation
import Shared

struct OpenAIResponsesAPI: CloudChatAPI {
    static let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    var configuration: CloudCleanupConfiguration
    var system: String
    var transcript: String
    var screenshot: Data?
    var input: [JSONValue]

    init(configuration: CloudCleanupConfiguration, system: String, transcript: String, screenshot: Data? = nil) {
        self.configuration = configuration
        self.system = system
        self.transcript = transcript
        self.screenshot = screenshot
        input = [Self.userMessage(transcript, screenshot: screenshot)]
    }

    static func userMessage(_ transcript: String, screenshot: Data?) -> JSONValue {
        let text = CloudCleanupPrompt.user(transcript)
        guard let screenshot else { return ["role": "user", "content": .string(text)] }
        return [
            "role": "user",
            "content": [
                ["type": "input_image", "image_url": .string(CloudCleanupPrompt.screenshotURL(screenshot)), "detail": "auto"],
                ["type": "input_text", "text": .string(text)],
            ],
        ]
    }

    /// GPT-6 Astra and GPT-6.1 Sol reject `none`, and the first GPT-5 models accept only `minimal`.
    static func reasoningEffort(for model: CloudModel.ID) -> String? {
        let id = model.rawValue.lowercased()
        if id.hasPrefix("gpt-6-luna") || id.hasPrefix("gpt-6-sol") { return "none" }
        if id.hasPrefix("gpt-6") { return "low" }
        if ["gpt-5", "gpt-5-mini", "gpt-5-nano"].contains(where: { id == $0 || id.hasPrefix("\($0)-20") }) { return "minimal" }
        if id.hasPrefix("gpt-5") { return "none" }
        if id.hasPrefix("o1") || id.hasPrefix("o3") || id.hasPrefix("o4") { return "low" }
        return nil
    }

    var tools: [JSONValue] {
        var tools: [JSONValue] = CloudCleanupPrompt.functionTools(for: configuration.tools).map { tool in
            [
                "type": "function",
                "name": .string(tool.name),
                "description": .string(tool.description),
                "parameters": CloudCleanupPrompt.emptyParameters,
                "strict": true,
            ]
        }
        if configuration.tools.contains(.webSearch) {
            tools.append(["type": "web_search"])
        }
        return tools
    }

    func request() throws -> URLRequest {
        try configuration.connection.requireAPIKey()
        var body: [String: JSONValue] = [
            "model": .string(configuration.model.rawValue),
            "store": false,
            "instructions": .string(system),
            "input": .array(input),
        ]
        if let effort = Self.reasoningEffort(for: configuration.model) {
            body["reasoning"] = ["effort": .string(effort)]
            body["include"] = ["reasoning.encrypted_content"]
        }
        if !tools.isEmpty {
            body["tools"] = .array(tools)
        }
        return try CloudHTTP.request(
            Self.endpoint,
            headers: ["Authorization": "Bearer \(configuration.connection.apiKey)"],
            body: .object(body),
            timeout: CloudHTTP.timeout(for: configuration.tools)
        )
    }

    mutating func receive(_ response: JSONValue) throws -> CloudTurn {
        if let message = response["error"]?["message"]?.stringValue {
            throw CloudCleanupError.provider(message)
        }
        let output = response["output"]?.arrayValue ?? []
        input.append(contentsOf: output)

        let calls = output.compactMap { item -> CloudToolCall? in
            guard item["type"]?.stringValue == "function_call",
                  let id = item["call_id"]?.stringValue,
                  let name = item["name"]?.stringValue
            else { return nil }
            return CloudToolCall(id: CloudToolCall.ID(rawValue: id), name: name, arguments: item["arguments"]?.stringValue ?? "{}")
        }
        if !calls.isEmpty {
            return .toolCalls(calls)
        }

        let messages = output.filter { $0["type"]?.stringValue == "message" }
        let finalAnswers = messages.filter { $0["phase"]?.stringValue == "final_answer" }
        let text = (finalAnswers.isEmpty ? messages : finalAnswers)
            .flatMap { $0["content"]?.arrayValue ?? [] }
            .filter { $0["type"]?.stringValue == "output_text" }
            .compactMap { $0["text"]?.stringValue }
            .joined()
        return .finished(text: text, model: response["model"]?.stringValue.map { CloudModel.ID(rawValue: $0) })
    }

    /// A model that cannot read images rejects the screenshot, so the request goes again without it.
    mutating func adapt(to error: CloudCleanupError) -> Bool {
        guard screenshot != nil, error.rejectsImages else { return false }
        screenshot = nil
        input[0] = Self.userMessage(transcript, screenshot: nil)
        return true
    }

    mutating func appendToolResults(_ results: [CloudToolResult]) {
        input += results.map { result in
            ["type": "function_call_output", "call_id": .string(result.call.id.rawValue), "output": .string(result.output)]
        }
    }
}
