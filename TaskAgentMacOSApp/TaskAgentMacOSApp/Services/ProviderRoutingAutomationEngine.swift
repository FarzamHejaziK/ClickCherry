import Foundation

struct ProviderRoutingAutomationEngine: AutomationEngine {
    private let apiKeyStore: any APIKeyStore
    private let openAIEngine: any AutomationEngine
    private let anthropicEngine: any AutomationEngine
    private let preferredProvider: @Sendable () -> ExecutionProvider

    init(
        apiKeyStore: any APIKeyStore,
        openAIEngine: any AutomationEngine,
        anthropicEngine: any AutomationEngine,
        preferredProvider: @escaping @Sendable () -> ExecutionProvider
    ) {
        self.apiKeyStore = apiKeyStore
        self.openAIEngine = openAIEngine
        self.anthropicEngine = anthropicEngine
        self.preferredProvider = preferredProvider
    }

    func run(taskMarkdown: String) async -> AutomationRunResult {
        let selectedProvider = preferredProvider()
        switch selectedProvider {
        case .openAI:
            if apiKeyStore.hasKey(for: .openAI) {
                return await openAIEngine.run(taskMarkdown: taskMarkdown)
            }
            return missingKeyResult(for: .openAI)
        case .anthropic:
            if apiKeyStore.hasKey(for: .anthropic) {
                return await anthropicEngine.run(taskMarkdown: taskMarkdown)
            }
            return missingKeyResult(for: .anthropic)
        }
    }

    private func missingKeyResult(for provider: ExecutionProvider) -> AutomationRunResult {
        let otherProvider: ExecutionProvider = provider == .openAI ? .anthropic : .openAI
        let otherProviderConfigured = apiKeyStore.hasKey(for: otherProvider.apiKeyProviderIdentifier)
        let errorMessage: String
        if otherProviderConfigured {
            errorMessage =
                "Selected execution provider is \(provider.displayName), but no \(provider.displayName) API key is saved. Save a \(provider.displayName) key or switch execution provider to \(otherProvider.displayName)."
        } else {
            errorMessage =
                "Selected execution provider is \(provider.displayName), but no \(provider.displayName) API key is saved. Save a \(provider.displayName) API key in Provider API Keys."
        }

        return AutomationRunResult(
            outcome: .failed,
            executedSteps: [],
            generatedQuestions: [],
            errorMessage: errorMessage,
            llmSummary: nil
        )
    }
}
