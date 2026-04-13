import Foundation
import Security
import Testing
@testable import TaskAgentMacOSApp

private final class InMemoryBrowserBridgeTokenStore: BrowserBridgeTokenStore {
    var token: String?
    var shouldFailWrites = false

    func hasPlaywrightMCPBridgeToken() -> Bool {
        guard let token else { return false }
        return !token.isEmpty
    }

    func readPlaywrightMCPBridgeToken() throws -> String? {
        token
    }

    func setPlaywrightMCPBridgeToken(_ token: String?) throws {
        if shouldFailWrites {
            throw KeychainStoreError.unhandledStatus(errSecParam)
        }
        self.token = token
    }
}

private final class BrowserAutomationTestAPIKeyStore: APIKeyStore {
    private var keys: [ProviderIdentifier: String]

    init(keys: [ProviderIdentifier: String] = [.openAI: "openai", .gemini: "gemini"]) {
        self.keys = keys
    }

    func hasKey(for provider: ProviderIdentifier) -> Bool {
        guard let value = keys[provider] else { return false }
        return !value.isEmpty
    }

    func readKey(for provider: ProviderIdentifier) throws -> String? {
        keys[provider]
    }

    func setKey(_ key: String?, for provider: ProviderIdentifier) throws {
        keys[provider] = key
    }
}

struct MainShellStateStoreBrowserAutomationTests {
    @Test
    func savePlaywrightBridgeTokenUpdatesStateAndEnvironment() throws {
        let tokenStore = InMemoryBrowserBridgeTokenStore()
        let suiteName = "MainShellStateStoreBrowserAutomationTests.save.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = MainShellStateStore(
            apiKeyStore: BrowserAutomationTestAPIKeyStore(),
            browserBridgeTokenStore: tokenStore,
            userDefaults: defaults
        )
        defer {
            MainShellStateStore.applyPlaywrightMCPBridgeTokenEnvironment(token: nil)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let saved = store.savePlaywrightMCPBridgeToken("bridge-token-123")

        #expect(saved)
        #expect(tokenStore.token == "bridge-token-123")
        #expect(store.browserAutomationSetupState.hasPlaywrightMCPBridgeToken)
        #expect(store.browserAutomationStatusMessage == "Saved Playwright MCP Bridge token.")
        #expect(processEnvironmentValue(for: MainShellStateStore.playwrightMCPBridgeTokenEnvironmentKey) == "bridge-token-123")
    }

    @Test
    func clearPlaywrightBridgeTokenUpdatesStateAndEnvironment() throws {
        let tokenStore = InMemoryBrowserBridgeTokenStore()
        tokenStore.token = "existing-token"
        let suiteName = "MainShellStateStoreBrowserAutomationTests.clear.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = MainShellStateStore(
            apiKeyStore: BrowserAutomationTestAPIKeyStore(),
            browserBridgeTokenStore: tokenStore,
            userDefaults: defaults
        )
        defer {
            MainShellStateStore.applyPlaywrightMCPBridgeTokenEnvironment(token: nil)
            defaults.removePersistentDomain(forName: suiteName)
        }

        store.clearPlaywrightMCPBridgeToken()

        #expect(tokenStore.token == nil)
        #expect(!store.browserAutomationSetupState.hasPlaywrightMCPBridgeToken)
        #expect(store.browserAutomationStatusMessage == "Removed Playwright MCP Bridge token.")
        #expect(processEnvironmentValue(for: MainShellStateStore.playwrightMCPBridgeTokenEnvironmentKey) == nil)
    }

    private func processEnvironmentValue(for key: String) -> String? {
        guard let raw = getenv(key), let value = String(validatingUTF8: raw) else {
            return nil
        }
        return value
    }
}
