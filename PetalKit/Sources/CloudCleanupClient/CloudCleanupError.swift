import Foundation
import Shared

public enum CloudCleanupError: LocalizedError, Equatable, Sendable {
    case missingAPIKey(CloudProvider)
    case invalidBaseURL
    case http(status: Int, message: String?)
    case provider(String)
    case invalidResponse
    case emptyResponse
    case refused
    case tooManyToolCalls

    public var errorDescription: String? {
        switch self {
        case let .missingAPIKey(provider):
            "Add your \(provider.displayName) API key."
        case .invalidBaseURL:
            "Enter a server URL, such as http://localhost:11434/v1."
        case let .http(status, message):
            "\(message ?? HTTPURLResponse.localizedString(forStatusCode: status).capitalized) (HTTP \(status))"
        case let .provider(message):
            message
        case .invalidResponse:
            "The provider sent a response that Petal could not read."
        case .emptyResponse:
            "The model returned no text."
        case .refused:
            "The model declined this request."
        case .tooManyToolCalls:
            "The model called its tools too many times without an answer."
        }
    }

    public var isAuthenticationFailure: Bool {
        guard case let .http(status, _) = self else { return false }
        return status == 401 || status == 403
    }

    var rejectsImages: Bool {
        guard case let .http(status, message) = self, (400 ..< 500).contains(status) else { return false }
        return message?.localizedCaseInsensitiveContains("image") == true
    }
}
