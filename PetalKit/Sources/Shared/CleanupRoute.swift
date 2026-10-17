import Foundation

/// Instructions that replace the default cleanup prompt while the user dictates into one app or website.
public struct CleanupRoute: Codable, Equatable, Identifiable, Sendable {
    public typealias ID = Tagged<Self, UUID>

    @CasePathable
    @dynamicMemberLookup
    public enum Trigger: Codable, Hashable, Sendable {
        case app(MacApp)
        case website(String)
    }

    public enum Action: String, Codable, Sendable {
        case cleanUp
        case pasteAsSaid
    }

    public var id: ID
    public var trigger: Trigger
    public var action: Action
    /// Kept while the action is `pasteAsSaid`, so turning cleanup back on restores it.
    public var prompt: String
    /// Cleanup engine for this route. `nil` uses the one chosen in Intelligence.
    public var cleanupModel: CleanupModel?

    public init(
        id: ID,
        trigger: Trigger,
        action: Action = .cleanUp,
        prompt: String,
        cleanupModel: CleanupModel? = nil
    ) {
        self.id = id
        self.trigger = trigger
        self.action = action
        self.prompt = prompt
        self.cleanupModel = cleanupModel
    }

    /// Accepts what people paste, such as "https://www.github.com/apple", and keeps only "github.com".
    public static func domain(from input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            text = "https://\(text)"
        }
        guard let host = URL(string: text)?.host(), host.contains(".") || host == "localhost" else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    public static func host(_ host: String, isOn domain: String) -> Bool {
        let host = host.lowercased()
        return host == domain || host.hasSuffix(".\(domain)")
    }
}

public extension Collection where Element == CleanupRoute {
    /// A website route wins over an app route, so a browser can use one style on GitHub and another everywhere else.
    func route(for focusedApp: FocusedApp?) -> CleanupRoute? {
        guard let focusedApp else { return nil }
        if let host = focusedApp.website,
           let route = first(where: { $0.trigger.website.map { CleanupRoute.host(host, isOn: $0) } ?? false })
        {
            return route
        }
        return first { $0.trigger.app?.bundleID == focusedApp.app.bundleID }
    }

    func route(with trigger: CleanupRoute.Trigger) -> CleanupRoute? {
        first { route in
            switch (route.trigger, trigger) {
            case let (.app(lhs), .app(rhs)): lhs.bundleID == rhs.bundleID
            case let (.website(lhs), .website(rhs)): lhs == rhs
            default: false
            }
        }
    }
}
