import Foundation

protocol LLMClient {
    func analyzeVideo(at url: URL, prompt: String, model: String) async throws -> String
}

protocol AutomationEngine {
    func run(taskMarkdown: String) async throws
}

protocol Scheduler {
    func schedule(taskId: String, expression: String) throws
}

enum LLMClientError: Error, Equatable {
    case notConfigured
}

struct UnconfiguredLLMClient: LLMClient {
    func analyzeVideo(at url: URL, prompt: String, model: String) async throws -> String {
        throw LLMClientError.notConfigured
    }
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
