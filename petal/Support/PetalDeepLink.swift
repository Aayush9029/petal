import Foundation

enum PetalDeepLinkCommand: String, Sendable {
    case start
    case stop
    case toggle
    case setup
    case settings
    case checkForUpdates = "check-for-updates"

    static func parse(_ url: URL) -> Self? {
        guard url.scheme?.lowercased() == "petal" else { return nil }

        let hostToken = normalizedToken(url.host ?? "")
        if let command = Self(rawValue: hostToken) {
            return command
        }

        let pathToken = normalizedToken(url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        if let command = Self(rawValue: pathToken) {
            return command
        }

        return nil
    }

    private static func normalizedToken(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
    }
}
