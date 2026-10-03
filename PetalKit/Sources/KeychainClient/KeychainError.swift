import Foundation
import Security

public struct KeychainError: LocalizedError, Equatable, Sendable {
    public var status: OSStatus

    public var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
        return "The keychain could not save the key. \(message) (\(status))"
    }
}
