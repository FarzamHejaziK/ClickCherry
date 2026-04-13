import Foundation

protocol LLMClient {
    func analyzeVideo(at url: URL, prompt: String, model: String) async throws -> String
}

enum AutomationRunOutcome: String, Equatable, Codable, Sendable {
    case success
    case needsClarification
    case failed
    case cancelled
}

struct AutomationRunResult: Equatable {
    var outcome: AutomationRunOutcome
    var executedSteps: [String]
    var generatedQuestions: [String]
    var errorMessage: String?
    var llmSummary: String?
    var llmUserFacingIssue: LLMUserFacingIssue? = nil
}

struct AutomationRunSummary: Equatable {
    var startedAt: Date
    var finishedAt: Date
    var outcome: AutomationRunOutcome
    var executedSteps: [String]
    var generatedQuestions: [String]
    var errorMessage: String?
    var llmSummary: String?
}

protocol AutomationEngine {
    func run(taskMarkdown: String) async -> AutomationRunResult
}

protocol LLMExecutionToolLoopRunner {
    func runToolLoop(taskMarkdown: String, executor: any DesktopActionExecutor) async throws -> AutomationRunResult
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
    var hasGeminiKey: Bool

    var hasCoreProvider: Bool {
        hasOpenAIKey
    }

    var isReadyForOnboardingCompletion: Bool {
        hasOpenAIKey && hasGeminiKey
    }
}

struct BrowserAutomationSetupState: Equatable {
    var hasPlaywrightMCPBridgeToken: Bool
}

enum LLMProvider: String, Equatable, Sendable, Codable {
    case openAI
    case gemini
}

enum LLMOperation: String, Equatable, Sendable, Codable {
    case taskExtraction
    case execution
}

enum LLMCallOutcome: String, Equatable, Sendable, Codable {
    case success
    case failure
}

enum LLMScreenshotSource: String, Equatable, Sendable, Codable {
    case initialPromptImage = "initial_prompt_image"
    case actionScreenshot = "action_screenshot"
    case postActionSnapshot = "post_action_snapshot"
}

struct LLMScreenshotLogEntry: Identifiable, Equatable, Sendable {
    var id: UUID
    var timestamp: Date
    var source: LLMScreenshotSource
    var mediaType: String
    var width: Int
    var height: Int
    var captureWidthPx: Int
    var captureHeightPx: Int
    var coordinateSpaceWidthPx: Int
    var coordinateSpaceHeightPx: Int
    var rawByteCount: Int
    var base64ByteCount: Int
    var imageData: Data

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: LLMScreenshotSource,
        mediaType: String,
        width: Int,
        height: Int,
        captureWidthPx: Int,
        captureHeightPx: Int,
        coordinateSpaceWidthPx: Int,
        coordinateSpaceHeightPx: Int,
        rawByteCount: Int,
        base64ByteCount: Int,
        imageData: Data
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.mediaType = mediaType
        self.width = width
        self.height = height
        self.captureWidthPx = captureWidthPx
        self.captureHeightPx = captureHeightPx
        self.coordinateSpaceWidthPx = coordinateSpaceWidthPx
        self.coordinateSpaceHeightPx = coordinateSpaceHeightPx
        self.rawByteCount = rawByteCount
        self.base64ByteCount = base64ByteCount
        self.imageData = imageData
    }
}

enum ExecutionTraceKind: String, Equatable, Sendable {
    case info
    case llmResponse
    case toolUse
    case localAction
    case completion
    case cancelled
    case error
}

struct ExecutionTraceEntry: Identifiable, Equatable, Sendable {
    var id: UUID
    var timestamp: Date
    var kind: ExecutionTraceKind
    var message: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: ExecutionTraceKind,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.message = message
    }
}

struct LLMCallLogEntry: Identifiable, Equatable, Sendable {
    var id: UUID
    var startedAt: Date
    var finishedAt: Date
    var provider: LLMProvider
    var operation: LLMOperation
    var attempt: Int
    var url: String
    var httpStatus: Int?
    var requestId: String?
    var bytesSent: Int?
    var bytesReceived: Int?
    var outcome: LLMCallOutcome
    var message: String?

    init(
        id: UUID = UUID(),
        startedAt: Date,
        finishedAt: Date,
        provider: LLMProvider,
        operation: LLMOperation,
        attempt: Int,
        url: String,
        httpStatus: Int? = nil,
        requestId: String? = nil,
        bytesSent: Int? = nil,
        bytesReceived: Int? = nil,
        outcome: LLMCallOutcome,
        message: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.provider = provider
        self.operation = operation
        self.attempt = attempt
        self.url = url
        self.httpStatus = httpStatus
        self.requestId = requestId
        self.bytesSent = bytesSent
        self.bytesReceived = bytesReceived
        self.outcome = outcome
        self.message = message
    }

    var durationMs: Int {
        Int(finishedAt.timeIntervalSince(startedAt) * 1000.0)
    }
}

struct LLMExchangeLogEntry: Identifiable, Equatable, Sendable {
    var id: UUID
    var startedAt: Date
    var finishedAt: Date
    var provider: LLMProvider
    var operation: LLMOperation
    var attempt: Int
    var url: String
    var httpStatus: Int?
    var requestId: String?
    var outcome: LLMCallOutcome
    var requestBodyData: Data
    var responseBodyData: Data?

    init(
        id: UUID = UUID(),
        startedAt: Date,
        finishedAt: Date,
        provider: LLMProvider,
        operation: LLMOperation,
        attempt: Int,
        url: String,
        httpStatus: Int? = nil,
        requestId: String? = nil,
        outcome: LLMCallOutcome,
        requestBodyData: Data,
        responseBodyData: Data? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.provider = provider
        self.operation = operation
        self.attempt = attempt
        self.url = url
        self.httpStatus = httpStatus
        self.requestId = requestId
        self.outcome = outcome
        self.requestBodyData = requestBodyData
        self.responseBodyData = responseBodyData
    }
}
