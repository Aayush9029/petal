import Dependencies
import DependenciesMacros
import Foundation
import Security
import Tagged

@DependencyClient
public struct KeychainClient: Sendable {
    public typealias Account = Tagged<Self, String>

    public var string: @Sendable (_ account: Account) -> String? = { _ in nil }
    public var setString: @Sendable (_ value: String, _ account: Account) throws -> Void
    public var delete: @Sendable (_ account: Account) throws -> Void
}

extension KeychainClient: DependencyKey {
    public static var liveValue: Self {
        let service = "com.optimalapps.petal"
        return Self(
            string: { account in
                var item: CFTypeRef?
                let query = baseQuery(service: service, account: account).merging([
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne,
                ]) { $1 }
                guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                      let data = item as? Data
                else { return nil }
                return String(data: data, encoding: .utf8)
            },
            setString: { value, account in
                let query = baseQuery(service: service, account: account)
                let data = Data(value.utf8)
                let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
                if status == errSecItemNotFound {
                    let attributes = query.merging([
                        kSecValueData as String: data,
                        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                        kSecAttrLabel as String: "Petal API key",
                    ]) { $1 }
                    try check(SecItemAdd(attributes as CFDictionary, nil))
                } else {
                    try check(status)
                }
            },
            delete: { account in
                let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
                guard status != errSecItemNotFound else { return }
                try check(status)
            }
        )
    }

    public static var previewValue: Self { .inMemory() }

    public static var testValue: Self { Self() }

    private static func baseQuery(service: String, account: Account) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
    }

    private static func check(_ status: OSStatus) throws {
        guard status != errSecSuccess else { return }
        throw KeychainError(status: status)
    }
}

public extension KeychainClient {
    static func inMemory(_ initialValues: [Account: String] = [:]) -> Self {
        let values = LockIsolated(initialValues)
        return Self(
            string: { values.value[$0] },
            setString: { value, account in values.withValue { $0[account] = value } },
            delete: { account in values.withValue { $0[account] = nil } }
        )
    }
}

public extension DependencyValues {
    var keychainClient: KeychainClient {
        get { self[KeychainClient.self] }
        set { self[KeychainClient.self] = newValue }
    }
}
