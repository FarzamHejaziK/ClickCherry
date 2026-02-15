import Foundation
import Security

enum ProviderIdentifier: String, CaseIterable {
    case openAI
    case gemini
}

protocol APIKeyStore {
    func hasKey(for provider: ProviderIdentifier) -> Bool
    func readKey(for provider: ProviderIdentifier) throws -> String?
    func setKey(_ key: String?, for provider: ProviderIdentifier) throws
}

protocol OnboardingCompletionStore {
    var hasCompletedOnboarding: Bool { get set }
}

enum KeychainStoreError: Error {
    case unhandledStatus(OSStatus)
}

final class KeychainAPIKeyStore: APIKeyStore {
    private let service = "com.taskagentmacos.apikeys"
    private static let presenceCacheLock = NSLock()
    private static var cachedPresenceByProvider: [ProviderIdentifier: Bool]?
    private static let testStorageLock = NSLock()
    private static var testStorage: [ProviderIdentifier: String] = [:]

    private var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func hasKey(for provider: ProviderIdentifier) -> Bool {
        if isRunningUnderXCTest {
            guard let key = Self.readTestValue(for: provider) else {
                return false
            }
            return !key.isEmpty
        }

        if let cached = Self.readPresenceFromCache(for: provider) {
            return cached
        }

        let loadedPresence = loadPresenceMapFromKeychain()
        Self.writePresenceCache(loadedPresence)
        if let cached = loadedPresence[provider] {
            return cached
        }
        return false
    }

    func readKey(for provider: ProviderIdentifier) throws -> String? {
        if isRunningUnderXCTest {
            return Self.readTestValue(for: provider)
        }

        var query = keychainQuery(for: provider)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unhandledStatus(status)
        }

        guard let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func setKey(_ key: String?, for provider: ProviderIdentifier) throws {
        if isRunningUnderXCTest {
            Self.writeTestValue(key, for: provider)
            return
        }

        let query = keychainQuery(for: provider)

        if let key {
            let data = Data(key.utf8)
            let attributes: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

            if updateStatus == errSecSuccess {
                Self.updatePresenceCache(for: provider, hasKey: true)
                return
            }

            if updateStatus == errSecItemNotFound {
                var createQuery = query
                createQuery[kSecValueData as String] = data
                let addStatus = SecItemAdd(createQuery as CFDictionary, nil)
                guard addStatus == errSecSuccess else {
                    throw KeychainStoreError.unhandledStatus(addStatus)
                }
                Self.updatePresenceCache(for: provider, hasKey: true)
                return
            }

            throw KeychainStoreError.unhandledStatus(updateStatus)
        }

        let deleteStatus = SecItemDelete(query as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw KeychainStoreError.unhandledStatus(deleteStatus)
        }
        Self.updatePresenceCache(for: provider, hasKey: false)
    }

    private func keychainQuery(for provider: ProviderIdentifier) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
    }

    private static func readTestValue(for provider: ProviderIdentifier) -> String? {
        testStorageLock.lock()
        defer { testStorageLock.unlock() }
        return testStorage[provider]
    }

    private static func writeTestValue(_ key: String?, for provider: ProviderIdentifier) {
        testStorageLock.lock()
        defer { testStorageLock.unlock() }
        testStorage[provider] = key
    }

    private func loadPresenceMapFromKeychain() -> [ProviderIdentifier: Bool] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return [:]
        }
        guard status == errSecSuccess else {
            return [:]
        }

        var presence: [ProviderIdentifier: Bool] = [:]
        if let rows = result as? [[String: Any]] {
            for row in rows {
                if let provider = providerIdentifier(from: row) {
                    presence[provider] = true
                }
            }
            return presence
        }

        if let row = result as? [String: Any], let provider = providerIdentifier(from: row) {
            presence[provider] = true
        }
        return presence
    }

    private func providerIdentifier(from attributes: [String: Any]) -> ProviderIdentifier? {
        guard let account = attributes[kSecAttrAccount as String] as? String else {
            return nil
        }
        return ProviderIdentifier(rawValue: account)
    }

    private static func readPresenceFromCache(for provider: ProviderIdentifier) -> Bool? {
        presenceCacheLock.lock()
        defer { presenceCacheLock.unlock() }
        guard let cache = cachedPresenceByProvider else {
            return nil
        }
        return cache[provider] ?? false
    }

    private static func writePresenceCache(_ cache: [ProviderIdentifier: Bool]) {
        presenceCacheLock.lock()
        defer { presenceCacheLock.unlock() }
        cachedPresenceByProvider = cache
    }

    private static func updatePresenceCache(for provider: ProviderIdentifier, hasKey: Bool) {
        presenceCacheLock.lock()
        defer { presenceCacheLock.unlock() }
        guard var cache = cachedPresenceByProvider else {
            return
        }
        cache[provider] = hasKey
        cachedPresenceByProvider = cache
    }
}

final class UserDefaultsOnboardingCompletionStore: OnboardingCompletionStore {
    private let defaults: UserDefaults
    private let key = "onboarding.completed"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}
