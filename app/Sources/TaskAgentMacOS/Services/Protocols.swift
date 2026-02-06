import Foundation

protocol LLMClient {
    func analyzeVideo(at url: URL) async throws -> String
}

protocol AutomationEngine {
    func run(taskMarkdown: String) async throws
}

protocol Scheduler {
    func schedule(taskId: String, expression: String) throws
}

struct ProviderSetupState: Equatable {
    var hasOpenAIKey: Bool
    var hasAnthropicKey: Bool
    var hasGeminiKey: Bool

    var hasCoreProvider: Bool {
        hasOpenAIKey || hasAnthropicKey
    }

    var isReadyForOnboardingCompletion: Bool {
        hasCoreProvider && hasGeminiKey
    }
}
