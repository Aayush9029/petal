import RouterFeature
import Shared

extension RouterModel.Style {
    var title: String {
        switch self {
        case let .preset(preset): preset.title
        case .custom: "Custom"
        case .pasteAsSaid: "As Said"
        }
    }

    /// The route cards show the app name above, so "Custom Prompt" reads clearly there.
    var nodeTitle: String {
        switch self {
        case let .preset(preset): preset.title
        case .custom: "Custom Prompt"
        case .pasteAsSaid: "As Said"
        }
    }

    var symbol: String {
        switch self {
        case let .preset(preset): preset.symbol
        case .custom: "square.and.pencil"
        case .pasteAsSaid: "quote.bubble"
        }
    }

    var summary: String {
        switch self {
        case let .preset(preset): preset.summary
        case .custom: "Follows instructions you write."
        case .pasteAsSaid: "Skips cleanup and pastes your words."
        }
    }
}

extension CleanupRoute.Trigger {
    var title: String {
        switch self {
        case let .app(app): app.name
        case let .website(domain): domain
        }
    }
}
