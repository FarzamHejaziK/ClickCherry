import Testing
import Security
@testable import TaskAgentMacOS

private final class InMemoryAPIKeyStore: APIKeyStore {
    var keys: [ProviderIdentifier: String]
    var shouldFailWrites: Bool

    init(keys: [ProviderIdentifier: String] = [:], shouldFailWrites: Bool = false) {
        self.keys = keys
        self.shouldFailWrites = shouldFailWrites
    }

    func hasKey(for provider: ProviderIdentifier) -> Bool {
        guard let value = keys[provider] else {
            return false
        }

        return !value.isEmpty
    }

    func setKey(_ key: String?, for provider: ProviderIdentifier) throws {
        if shouldFailWrites {
            throw KeychainStoreError.unhandledStatus(errSecParam)
        }

        if key == nil {
            keys.removeValue(forKey: provider)
        } else {
            keys[provider] = key
        }
    }
}

private final class MockPermissionService: PermissionService {
    var statuses: [AppPermission: PermissionGrantStatus]

    init(statuses: [AppPermission: PermissionGrantStatus] = [:]) {
        self.statuses = statuses
    }

    func openSystemSettings(for permission: AppPermission) {}

    func currentStatus(for permission: AppPermission) -> PermissionGrantStatus {
        statuses[permission] ?? .unknown
    }
}

private final class InMemoryOnboardingCompletionStore: OnboardingCompletionStore {
    var hasCompletedOnboarding: Bool

    init(hasCompletedOnboarding: Bool) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
}

struct OnboardingPersistenceTests {
    @Test
    func initializesProviderStateFromKeyStore() {
        let keyStore = InMemoryAPIKeyStore(keys: [.anthropic: "anthropic-key", .gemini: "gemini-key"])
        let completionStore = InMemoryOnboardingCompletionStore(hasCompletedOnboarding: false)

        let store = OnboardingStateStore(
            keyStore: keyStore,
            completionStore: completionStore,
            permissionService: MockPermissionService()
        )

        #expect(!store.providerSetupState.hasOpenAIKey)
        #expect(store.providerSetupState.hasAnthropicKey)
        #expect(store.providerSetupState.hasGeminiKey)
    }

    @Test
    func saveProviderKeyPersistsIntoKeyStore() {
        let keyStore = InMemoryAPIKeyStore()
        let completionStore = InMemoryOnboardingCompletionStore(hasCompletedOnboarding: false)
        let store = OnboardingStateStore(
            keyStore: keyStore,
            completionStore: completionStore,
            permissionService: MockPermissionService()
        )

        let saved = store.saveProviderKey("open-ai-key", for: .openAI)
        #expect(saved)
        #expect(store.providerSetupState.hasOpenAIKey)
        #expect(keyStore.keys[.openAI] == "open-ai-key")

        store.clearProviderKey(for: .openAI)
        #expect(!store.providerSetupState.hasOpenAIKey)
        #expect(keyStore.keys[.openAI] == nil)
    }

    @Test
    func saveProviderKeyRejectsEmptyValue() {
        let keyStore = InMemoryAPIKeyStore()
        let completionStore = InMemoryOnboardingCompletionStore(hasCompletedOnboarding: false)
        let store = OnboardingStateStore(
            keyStore: keyStore,
            completionStore: completionStore,
            permissionService: MockPermissionService()
        )

        let saved = store.saveProviderKey("   ", for: .gemini)
        #expect(!saved)
        #expect(!store.providerSetupState.hasGeminiKey)
        #expect(store.persistenceErrorMessage != nil)
    }

    @Test
    func completionWritesToCompletionStore() {
        let keyStore = InMemoryAPIKeyStore(keys: [.openAI: "open-ai-key", .gemini: "gemini-key"])
        let completionStore = InMemoryOnboardingCompletionStore(hasCompletedOnboarding: false)
        let store = OnboardingStateStore(
            keyStore: keyStore,
            completionStore: completionStore,
            permissionService: MockPermissionService(),
            currentStep: .ready
        )

        store.completeOnboarding()
        #expect(completionStore.hasCompletedOnboarding)
        #expect(store.route == .mainShell)
    }

    @Test
    func showsPersistenceErrorWhenWriteFails() {
        let keyStore = InMemoryAPIKeyStore(shouldFailWrites: true)
        let completionStore = InMemoryOnboardingCompletionStore(hasCompletedOnboarding: false)
        let store = OnboardingStateStore(
            keyStore: keyStore,
            completionStore: completionStore,
            permissionService: MockPermissionService()
        )

        _ = store.saveProviderKey("gemini-key", for: .gemini)
        #expect(store.persistenceErrorMessage != nil)
    }
}
