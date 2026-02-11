import Foundation

struct ProviderRoutingAutomationEngine: AutomationEngine {
    private let apiKeyStore: any APIKeyStore
    private let openAIEngine: any AutomationEngine
    private let anthropicEngine: any AutomationEngine

    init(
        apiKeyStore: any APIKeyStore,
        openAIEngine: any AutomationEngine,
        anthropicEngine: any AutomationEngine
    ) {
        self.apiKeyStore = apiKeyStore
        self.openAIEngine = openAIEngine
        self.anthropicEngine = anthropicEngine
    }

    func run(taskMarkdown: String) async -> AutomationRunResult {
        if apiKeyStore.hasKey(for: .openAI) {
            return await openAIEngine.run(taskMarkdown: taskMarkdown)
        }

        if apiKeyStore.hasKey(for: .anthropic) {
            return await anthropicEngine.run(taskMarkdown: taskMarkdown)
        }

        return AutomationRunResult(
            outcome: .failed,
            executedSteps: [],
            generatedQuestions: [],
            errorMessage: "No execution provider key configured. Save an OpenAI or Anthropic API key in Provider API Keys.",
            llmSummary: nil
        )
    }
}
