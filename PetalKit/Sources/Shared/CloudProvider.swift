import CasePaths
import Foundation
import IdentifiedCollections
import Tagged

@CasePathable
public enum CloudProvider: String, CaseIterable, Identifiable, Sendable, Codable {
    case openAI = "openai"
    case anthropic
    case openRouter = "openrouter"
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .openRouter: "OpenRouter"
        case .custom: "Custom Server"
        }
    }

    public var defaultModel: CloudModel.ID {
        switch self {
        case .openAI: "gpt-6-luna"
        case .anthropic: "claude-opus-5-5"
        case .openRouter: "openai/gpt-6-luna"
        case .custom: ""
        }
    }

    public var suggestedModels: IdentifiedArrayOf<CloudModel> {
        switch self {
        case .openAI:
            [
                CloudModel(id: "gpt-6-luna", name: "GPT-6 Luna", note: "Fastest"),
                CloudModel(id: "gpt-6.1-sol", name: "GPT-6.1 Sol", note: "Balanced"),
                CloudModel(id: "gpt-6-astra", name: "GPT-6 Astra", note: "Most capable"),
            ]
        case .anthropic:
            [
                CloudModel(id: "claude-opus-5-5", name: "Claude Opus 5.5", note: "Best quality"),
                CloudModel(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5", note: "Faster"),
                CloudModel(id: "claude-haiku-4-5", name: "Claude Haiku 4.5", note: "Fastest"),
                CloudModel(id: "claude-fable-5-1", name: "Claude Fable 5.1", note: "Most capable"),
            ]
        case .openRouter:
            [
                CloudModel(id: "openai/gpt-6-luna", name: "OpenAI: GPT-6 Luna", note: "Fast"),
                CloudModel(id: "anthropic/claude-sonnet-5.5", name: "Anthropic: Claude Sonnet 5.5", note: "Balanced"),
                CloudModel(id: "google/gemini-3.8-flash", name: "Google: Gemini 3.8 Flash", note: "Fast"),
                CloudModel(id: "deepseek/deepseek-v4.1-flash", name: "DeepSeek: DeepSeek V4.1 Flash", note: "Low cost"),
                CloudModel(id: "anthropic/claude-opus-5.5", name: "Anthropic: Claude Opus 5.5", note: "Best quality"),
            ]
        case .custom:
            []
        }
    }

    public var apiKeyURL: URL? {
        switch self {
        case .openAI: URL(string: "https://platform.openai.com/api-keys")
        case .anthropic: URL(string: "https://platform.claude.com/settings/keys")
        case .openRouter: URL(string: "https://openrouter.ai/settings/keys")
        case .custom: nil
        }
    }

    public var apiKeyPlaceholder: String {
        switch self {
        case .openAI: "sk-proj-…"
        case .anthropic: "sk-ant-…"
        case .openRouter: "sk-or-…"
        case .custom: "Optional"
        }
    }

    public var requiresAPIKey: Bool { self != .custom }

    public var supportsWebSearch: Bool { self != .custom }

    public var supportsScreenshots: Bool { self != .custom }

    public static func owner(ofAPIKey key: String) -> Self? {
        if key.hasPrefix("sk-ant-") { return .anthropic }
        if key.hasPrefix("sk-or-") { return .openRouter }
        if key.hasPrefix("sk-") { return .openAI }
        return nil
    }
}
