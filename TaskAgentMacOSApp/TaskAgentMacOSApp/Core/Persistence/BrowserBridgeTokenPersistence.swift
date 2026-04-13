import Foundation
import Security

protocol BrowserBridgeTokenStore {
    func hasPlaywrightMCPBridgeToken() -> Bool
    func readPlaywrightMCPBridgeToken() throws -> String?
    func setPlaywrightMCPBridgeToken(_ token: String?) throws
}

final class KeychainBrowserBridgeTokenStore: BrowserBridgeTokenStore {
    private let service = "com.taskagentmacos.browserbridge"
    private let account = "playwright_mcp_extension_token"
    private static let testStorageLock = NSLock()
    private static var testToken: String?

    private var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func hasPlaywrightMCPBridgeToken() -> Bool {
        guard let token = try? readPlaywrightMCPBridgeToken() else {
            return false
        }
        return !token.isEmpty
    }

    func readPlaywrightMCPBridgeToken() throws -> String? {
        if isRunningUnderXCTest {
            return Self.readTestToken()
        }

        var query = keychainQuery()
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

    func setPlaywrightMCPBridgeToken(_ token: String?) throws {
        if isRunningUnderXCTest {
            Self.writeTestToken(token)
            return
        }

        let query = keychainQuery()
        let trimmedToken = token?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let trimmedToken, !trimmedToken.isEmpty {
            let data = Data(trimmedToken.utf8)
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

    private func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func readTestToken() -> String? {
        testStorageLock.lock()
        defer { testStorageLock.unlock() }
        return testToken
    }

    private static func writeTestToken(_ token: String?) {
        testStorageLock.lock()
        defer { testStorageLock.unlock() }
        testToken = token
    }
}
