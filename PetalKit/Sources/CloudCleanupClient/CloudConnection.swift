import Foundation
import Shared

public struct CloudConnection: Equatable, Sendable {
    public var provider: CloudProvider
    public var apiKey: String
    public var baseURL: String

    public init(provider: CloudProvider, apiKey: String = "", baseURL: String = "") {
        self.provider = provider
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    func customBaseURL() throws -> URL {
        var text = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") {
            text.removeLast()
        }
        if text.hasSuffix("/chat/completions") {
            text.removeLast("/chat/completions".count)
        }
        if !text.contains("://") {
            text = "http://\(text)"
        }
        guard let url = URL(string: text), let host = url.host(), !host.isEmpty else {
            throw CloudCleanupError.invalidBaseURL
        }
        return url
    }

    func requireAPIKey() throws {
        if provider.requiresAPIKey, apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CloudCleanupError.missingAPIKey(provider)
        }
    }
}
