import Foundation
import Shared

enum CloudModelCatalog {
    static func keyCheckRequest(for connection: CloudConnection) throws -> URLRequest {
        switch connection.provider {
        case .openRouter:
            try connection.requireAPIKey()
            // The model list is public, so only this endpoint proves the key.
            return try get(URL(string: "https://openrouter.ai/api/v1/key")!, connection: connection)
        case .openAI, .anthropic, .custom:
            return try listRequest(for: connection)
        }
    }

    static func listRequest(for connection: CloudConnection) throws -> URLRequest {
        switch connection.provider {
        case .openAI:
            try connection.requireAPIKey()
            return try get(URL(string: "https://api.openai.com/v1/models")!, connection: connection)
        case .anthropic:
            try connection.requireAPIKey()
            return try get(URL(string: "https://api.anthropic.com/v1/models?limit=1000")!, connection: connection)
        case .openRouter:
            return try get(URL(string: "https://openrouter.ai/api/v1/models")!, connection: connection)
        case .custom:
            return try get(connection.customBaseURL().appending(path: "models"), connection: connection)
        }
    }

    static func models(from response: JSONValue, provider: CloudProvider) -> IdentifiedArrayOf<CloudModel> {
        let entries = response["data"]?.arrayValue ?? []
        let models: [CloudModel] = switch provider {
        case .openAI:
            entries
                .filter { isOpenAIChatModel($0["id"]?.stringValue ?? "") }
                .sorted { ($0["created"]?.doubleValue ?? 0) > ($1["created"]?.doubleValue ?? 0) }
                .compactMap { model(id: $0["id"]) }
        case .anthropic:
            entries.compactMap { model(id: $0["id"], name: $0["display_name"]) }
        case .openRouter:
            entries
                .filter { $0["architecture"]?["output_modalities"]?.arrayValue?.contains("text") ?? true }
                .filter { !($0["id"]?.stringValue ?? "").hasSuffix(":batch") }
                .compactMap { model(id: $0["id"], name: $0["name"]) }
        case .custom:
            entries.compactMap { model(id: $0["id"]) }.sorted { $0.id.rawValue < $1.id.rawValue }
        }
        return IdentifiedArray(models, uniquingIDsWith: { first, _ in first })
    }

    static func isOpenAIChatModel(_ id: String) -> Bool {
        let excluded = ["audio", "realtime", "live", "tts", "transcribe", "image", "search", "embedding", "moderation", "instruct", "codex", "deep-research"]
        guard id.hasPrefix("gpt-") || id.hasPrefix("o1") || id.hasPrefix("o3") || id.hasPrefix("o4") else { return false }
        return !excluded.contains { id.contains($0) }
    }

    private static func model(id: JSONValue?, name: JSONValue? = nil) -> CloudModel? {
        guard let id = id?.stringValue, !id.isEmpty else { return nil }
        return CloudModel(id: CloudModel.ID(rawValue: id), name: name?.stringValue)
    }

    private static func get(_ url: URL, connection: CloudConnection) throws -> URLRequest {
        var headers: [String: String] = [:]
        let key = connection.apiKey
        switch connection.provider {
        case .anthropic:
            headers = ["x-api-key": key, "anthropic-version": AnthropicMessagesAPI.version]
        case .openAI, .openRouter, .custom:
            if !key.isEmpty {
                headers["Authorization"] = "Bearer \(key)"
            }
        }
        return try CloudHTTP.request(url, method: "GET", headers: headers, timeout: 15)
    }
}
