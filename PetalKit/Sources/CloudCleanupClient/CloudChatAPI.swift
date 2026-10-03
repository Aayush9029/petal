import Foundation
import Shared

protocol CloudChatAPI: Sendable {
    func request() throws -> URLRequest
    mutating func receive(_ response: JSONValue) throws -> CloudTurn
    mutating func appendToolResults(_ results: [CloudToolResult])
    mutating func adapt(to error: CloudCleanupError) -> Bool
}

extension CloudChatAPI {
    mutating func adapt(to error: CloudCleanupError) -> Bool { false }
}

struct CloudToolCall: Equatable, Identifiable, Sendable {
    typealias ID = Tagged<Self, String>

    var id: ID
    var name: String
    var arguments: String
}

struct CloudToolResult: Equatable, Sendable {
    var call: CloudToolCall
    var output: String
}

enum CloudTurn: Equatable, Sendable {
    case finished(text: String, model: CloudModel.ID?)
    case toolCalls([CloudToolCall])
    case paused
}
