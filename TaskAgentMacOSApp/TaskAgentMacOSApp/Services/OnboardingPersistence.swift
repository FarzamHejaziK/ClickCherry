import Foundation
import Security

enum ProviderIdentifier: String, CaseIterable {
    case openAI
    case anthropic
    case gemini
}

protocol APIKeyStore {
    func hasKey(for provider: ProviderIdentifier) -> Bool
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

    func hasKey(for provider: ProviderIdentifier) -> Bool {
        let query = keychainQuery(for: provider)
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    func setKey(_ key: String?, for provider: ProviderIdentifier) throws {
        let query = keychainQuery(for: provider)

        if let key {
            let data = Data(key.utf8)
            let attributes: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

            if updateStatus == errSecSuccess {
                return
            }

            if updateStatus == errSecItemNotFound {
                var createQuery = query
                createQuery[kSecValueData as String] = data
                let addStatus = SecItemAdd(createQuery as CFDictionary, nil)
                guard addStatus == errSecSuccess else {
                    throw KeychainStoreError.unhandledStatus(addStatus)
                }
                return
            }

            throw KeychainStoreError.unhandledStatus(updateStatus)
        }

        let deleteStatus = SecItemDelete(query as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw KeychainStoreError.unhandledStatus(deleteStatus)
        }
    }

    private func keychainQuery(for provider: ProviderIdentifier) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
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
