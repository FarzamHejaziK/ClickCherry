import Testing
@testable import TaskAgentMacOS

struct OnboardingStateStoreTests {
    @Test
    func defaultsToOnboardingRoute() {
        let store = OnboardingStateStore()
        #expect(store.route == .onboarding)
    }

    @Test
    func routesToMainShellWhenOpenAIAndGeminiExist() {
        let store = OnboardingStateStore(
            providerSetupState: ProviderSetupState(
                hasOpenAIKey: true,
                hasAnthropicKey: false,
                hasGeminiKey: true
            )
        )

        #expect(store.route == .mainShell)
    }

    @Test
    func routesToMainShellWhenAnthropicAndGeminiExist() {
        let store = OnboardingStateStore(
            providerSetupState: ProviderSetupState(
                hasOpenAIKey: false,
                hasAnthropicKey: true,
                hasGeminiKey: true
            )
        )

        #expect(store.route == .mainShell)
    }

    @Test
    func keepsOnboardingRouteWhenGeminiMissing() {
        let store = OnboardingStateStore(
            providerSetupState: ProviderSetupState(
                hasOpenAIKey: true,
                hasAnthropicKey: false,
                hasGeminiKey: false
            )
        )

        #expect(store.route == .onboarding)
    }
}
