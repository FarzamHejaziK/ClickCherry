import Testing
@testable import TaskAgentMacOS

struct ProviderSetupStateTests {
    @Test
    func requiresGeminiAndOneCoreProvider() {
        let none = ProviderSetupState(hasOpenAIKey: false, hasAnthropicKey: false, hasGeminiKey: false)
        #expect(!none.isReadyForOnboardingCompletion)

        let onlyGemini = ProviderSetupState(hasOpenAIKey: false, hasAnthropicKey: false, hasGeminiKey: true)
        #expect(!onlyGemini.isReadyForOnboardingCompletion)

        let openAIPlusGemini = ProviderSetupState(hasOpenAIKey: true, hasAnthropicKey: false, hasGeminiKey: true)
        #expect(openAIPlusGemini.isReadyForOnboardingCompletion)

        let anthropicPlusGemini = ProviderSetupState(hasOpenAIKey: false, hasAnthropicKey: true, hasGeminiKey: true)
        #expect(anthropicPlusGemini.isReadyForOnboardingCompletion)
    }
}
