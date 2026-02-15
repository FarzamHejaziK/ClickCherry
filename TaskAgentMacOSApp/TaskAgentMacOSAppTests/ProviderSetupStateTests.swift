import Testing
@testable import TaskAgentMacOSApp

struct ProviderSetupStateTests {
    @Test
    func requiresOpenAIAndGemini() {
        let none = ProviderSetupState(hasOpenAIKey: false, hasGeminiKey: false)
        #expect(!none.isReadyForOnboardingCompletion)

        let onlyGemini = ProviderSetupState(hasOpenAIKey: false, hasGeminiKey: true)
        #expect(!onlyGemini.isReadyForOnboardingCompletion)

        let openAIPlusGemini = ProviderSetupState(hasOpenAIKey: true, hasGeminiKey: true)
        #expect(openAIPlusGemini.isReadyForOnboardingCompletion)
    }
}
