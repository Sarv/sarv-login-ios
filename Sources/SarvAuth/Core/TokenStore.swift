import Foundation
import Security

/// Where tokens live between launches. The default is the Keychain; pass your
/// own (e.g. to share with an app extension) or `InMemoryTokenStore` in tests.
public protocol SarvTokenStore: AnyObject {
    func load() throws -> SarvTokens?
    func save(_ tokens: SarvTokens) throws
    func clear() throws
}

/// Keychain-backed store, one item per client id. Readable after first unlock,
/// never synced to iCloud or restored to another device.
public final class KeychainTokenStore: SarvTokenStore {

    private let service: String
    private let account: String
    private let accessGroup: String?

    public init(clientId: String, service: String = "com.sarv.auth", accessGroup: String? = nil) {
        self.service = service
        self.account = clientId
        self.accessGroup = accessGroup
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    public func load() throws -> SarvTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw SarvAuthError.keychain(status) }
        return try? JSONDecoder().decode(SarvTokens.self, from: data)
    }

    public func save(_ tokens: SarvTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add.merge(attributes) { $1 }
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SarvAuthError.keychain(status) }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SarvAuthError.keychain(status) }
    }
}

/// Process-lifetime store, for tests or apps that keep tokens elsewhere.
public final class InMemoryTokenStore: SarvTokenStore {
    private var tokens: SarvTokens?
    private let lock = NSLock()

    public init(tokens: SarvTokens? = nil) { self.tokens = tokens }

    public func load() throws -> SarvTokens? { lock.lock(); defer { lock.unlock() }; return tokens }
    public func save(_ tokens: SarvTokens) throws { lock.lock(); defer { lock.unlock() }; self.tokens = tokens }
    public func clear() throws { lock.lock(); defer { lock.unlock() }; tokens = nil }
}
