import Foundation
import Shared

public struct CloudPromptToken: Equatable, Sendable {
    @CasePathable
    public enum Kind: Equatable, Sendable {
        case tag
        case variable(CloudPromptVariable)
        case unknownVariable
    }

    public var kind: Kind
    public var range: NSRange

    public static func scan(_ text: String) -> [CloudPromptToken] {
        let fullRange = NSRange(text.startIndex..., in: text)
        let tags = tagPattern.matches(in: text, range: fullRange).map { CloudPromptToken(kind: .tag, range: $0.range) }
        let variables = variablePattern.matches(in: text, range: fullRange).map { match in
            let name = (text as NSString).substring(with: match.range(at: 1))
            return CloudPromptToken(
                kind: CloudPromptVariable(rawValue: name).map(Kind.variable) ?? .unknownVariable,
                range: match.range
            )
        }
        return (tags + variables).sorted { $0.range.location < $1.range.location }
    }

    private static let tagPattern = try! NSRegularExpression(pattern: "</?[A-Za-z_][A-Za-z0-9_-]*>")
    private static let variablePattern = try! NSRegularExpression(pattern: #"\{\{([A-Za-z_]+)\}\}"#)
}
