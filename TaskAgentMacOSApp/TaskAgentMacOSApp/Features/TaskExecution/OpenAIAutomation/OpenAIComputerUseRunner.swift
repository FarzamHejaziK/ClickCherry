import Foundation

enum OpenAIExecutionPlannerError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case failedToReadAPIKey
    case failedToLoadPrompt(String)
    case invalidResponse
    case requestFailed(String)
    case userFacingIssue(LLMUserFacingIssue)
    case screenshotCaptureFailed
    case invalidToolLoopResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is not configured. Save one in Provider API Keys."
        case .failedToReadAPIKey:
            return "Failed to read OpenAI API key from secure storage."
        case .failedToLoadPrompt(let promptName):
            return "Failed to load prompt '\(promptName)' from prompt catalog."
        case .invalidResponse:
            return "OpenAI response format was invalid."
        case .requestFailed(let reason):
            return "OpenAI task execution request failed: \(reason)"
        case .userFacingIssue(let issue):
            return issue.userMessage
        case .screenshotCaptureFailed:
            return "Failed to capture current desktop screenshot."
        case .invalidToolLoopResponse:
            return "OpenAI tool-loop response format was invalid."
        }
    }
}

struct OpenAICapturedScreenshot {
    var width: Int
    var height: Int
    var captureWidthPx: Int
    var captureHeightPx: Int
    var coordinateSpaceWidthPx: Int
    var coordinateSpaceHeightPx: Int
    var coordinateSpaceOriginX: Int
    var coordinateSpaceOriginY: Int
    var mediaType: String
    var base64Data: String
    var byteCount: Int
}

final class OpenAIComputerUseRunner: LLMExecutionToolLoopRunner {
    struct TransportRetryPolicy: Equatable {
        var maxAttempts: Int
        var baseDelaySeconds: Double
        var maxDelaySeconds: Double

        static let `default` = TransportRetryPolicy(
            maxAttempts: 5,
            baseDelaySeconds: 0.5,
            maxDelaySeconds: 6.0
        )
    }

    struct ParsedFunctionCall {
        var callID: String
        var name: String
        var arguments: String
    }

    enum PostActionVerificationDisposition {
        case noChange
        case require(stepDescription: String)
        case clear
    }

    struct ToolExecutionResult {
        var callID: String
        var output: String
        var isError: Bool
        var stepDescription: String?
        var generatedQuestions: [String]
        var followupVision: OpenAIFollowupVisionStrategy? = nil
        var verificationDisposition: PostActionVerificationDisposition = .noChange
    }

    struct CompletionResult {
        var outcome: AutomationRunOutcome
        var summary: String?
        var questions: [String]
        var errorMessage: String?
        var rawCompletionText: String?
    }

    struct TerminalExecToolResultPayload: Encodable {
        var ok: Bool
        var exitCode: Int
        var timedOut: Bool
        var stdout: String
        var stderr: String
        var truncated: Bool

        enum CodingKeys: String, CodingKey {
            case ok
            case exitCode = "exit_code"
            case timedOut = "timed_out"
            case stdout
            case stderr
            case truncated
        }
    }

    struct TerminalCommandExecutionResult {
        var exitCode: Int32
        var timedOut: Bool
        var stdout: Data
        var stderr: Data
        var truncated: Bool
    }

    final class PipeCollector {
        let lock = NSLock()
        let maxBytes: Int
        private(set) var truncated: Bool = false
        private var buffer = Data()

        init(maxBytes: Int) {
            self.maxBytes = max(0, maxBytes)
        }

        func append(_ chunk: Data) {
            lock.lock()
            defer { lock.unlock() }

            guard maxBytes > 0 else {
                truncated = true
                return
            }

            if buffer.count >= maxBytes {
                truncated = true
                return
            }

            let remaining = maxBytes - buffer.count
            if chunk.count <= remaining {
                buffer.append(chunk)
            } else {
                buffer.append(chunk.prefix(remaining))
                truncated = true
            }
        }

        func snapshot() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return buffer
        }
    }

    static let terminalExecMaxCapturedOutputBytes = 64 * 1024
    static let terminalExecDefaultTimeoutSeconds = 30.0
    static let terminalExecMaxTimeoutSeconds = 120.0
    static let terminalExecAlwaysVisualExecutables: Set<String> = [
        "osascript",
        "cliclick",
        "open"
    ]
    static let terminalExecVisualCommandKeywords: [String] = [
        "system events",
        "ui element",
        "click",
        "keystroke",
        "key code",
        "dock",
        "window",
        "menu bar",
        "mouse",
        "cursor",
        "screenshot",
        "screen shot",
        "screencapture"
    ]

    let apiKeyStore: any APIKeyStore
    let promptCatalog: PromptCatalogService
    let promptName: String
    let transportMode: OpenAIResponsesTransportMode
    let sessionFactory: @Sendable () -> URLSession
    let webSocketConnector: any OpenAIResponsesWebSocketConnecting
    let transportRetryPolicy: TransportRetryPolicy
    let sleepNanoseconds: @Sendable (UInt64) async -> Void
    let screenshotProvider: () throws -> OpenAICapturedScreenshot
    let cursorPositionProvider: () -> (x: Int, y: Int)?
    let screenshotLogSink: ((LLMScreenshotLogEntry) -> Void)?
    let callLogSink: ((LLMCallLogEntry) -> Void)?
    let exchangeLogSink: ((LLMExchangeLogEntry) -> Void)?
    let traceSink: ((ExecutionTraceEntry) -> Void)?

    let jsonDecoder = JSONDecoder()
    let jsonEncoder = JSONEncoder()

    var coordinateScaleX: Double = 1.0
    var coordinateScaleY: Double = 1.0
    var toolDisplayWidthPx: Int = 0
    var toolDisplayHeightPx: Int = 0
    var coordinateSpaceWidthPx: Int = 0
    var coordinateSpaceHeightPx: Int = 0
    var coordinateSpaceOriginX: Int = 0
    var coordinateSpaceOriginY: Int = 0
    var selectedDisplayCoordinateSpaceWidthPx: Int = 0
    var selectedDisplayCoordinateSpaceHeightPx: Int = 0
    var selectedDisplayCoordinateSpaceOriginX: Int = 0
    var selectedDisplayCoordinateSpaceOriginY: Int = 0
    var activeVisionState: OpenAIVisionViewState?

    init(
        apiKeyStore: any APIKeyStore,
        promptCatalog: PromptCatalogService = PromptCatalogService(),
        promptName: String = "execution_agent_openai",
        callLogSink: ((LLMCallLogEntry) -> Void)? = nil,
        exchangeLogSink: ((LLMExchangeLogEntry) -> Void)? = nil,
        screenshotLogSink: ((LLMScreenshotLogEntry) -> Void)? = nil,
        traceSink: ((ExecutionTraceEntry) -> Void)? = nil,
        session: URLSession = .shared,
        transportMode: OpenAIResponsesTransportMode = .http,
        webSocketConnector: (any OpenAIResponsesWebSocketConnecting)? = nil,
        transportRetryPolicy: TransportRetryPolicy = .default,
        sleepNanoseconds: @escaping @Sendable (UInt64) async -> Void = { nanos in
            try? await Task.sleep(nanoseconds: nanos)
        },
        beforeScreenshotCapture: (@Sendable () -> Void)? = nil,
        afterScreenshotCapture: (@Sendable () -> Void)? = nil,
        screenshotProvider: @escaping () throws -> OpenAICapturedScreenshot = OpenAIComputerUseRunner.captureMainDisplayScreenshot,
        cursorPositionProvider: @escaping () -> (x: Int, y: Int)? = OpenAIComputerUseRunner.currentCursorPosition
    ) {
        self.apiKeyStore = apiKeyStore
        self.promptCatalog = promptCatalog
        self.promptName = promptName
        self.callLogSink = callLogSink
        self.exchangeLogSink = exchangeLogSink
        self.screenshotLogSink = screenshotLogSink
        self.traceSink = traceSink
        self.transportMode = transportMode
        let configurationTemplate = Self.copySessionConfiguration(from: session.configuration)
        self.sessionFactory = {
            URLSession(configuration: Self.copySessionConfiguration(from: configurationTemplate))
        }
        self.webSocketConnector = webSocketConnector ?? URLSessionOpenAIResponsesWebSocketConnector(
            sessionFactory: {
                URLSession(configuration: Self.copySessionConfiguration(from: configurationTemplate))
            }
        )
        self.transportRetryPolicy = transportRetryPolicy
        self.sleepNanoseconds = sleepNanoseconds
        self.screenshotProvider = {
            beforeScreenshotCapture?()
            defer { afterScreenshotCapture?() }
            return try screenshotProvider()
        }
        self.cursorPositionProvider = cursorPositionProvider
    }

    func runToolLoop(taskMarkdown: String, executor: any DesktopActionExecutor) async throws -> AutomationRunResult {
        let promptTemplate = try loadPromptTemplate()
        let apiKey = try resolveAPIKey()
        let transportSession = makeResponsesTransportSession()
        defer { transportSession.finish() }

        let initialScreenshot: OpenAICapturedScreenshot
        do {
            initialScreenshot = try captureAndApplyFullDisplayScreenshotForLLM(
                source: .initialPromptImage,
                overlay: .none,
                gridSpacing: nil
            )
        } catch {
            throw OpenAIExecutionPlannerError.screenshotCaptureFailed
        }

        toolDisplayWidthPx = initialScreenshot.width
        toolDisplayHeightPx = initialScreenshot.height
        coordinateSpaceWidthPx = initialScreenshot.coordinateSpaceWidthPx
        coordinateSpaceHeightPx = initialScreenshot.coordinateSpaceHeightPx
        coordinateSpaceOriginX = initialScreenshot.coordinateSpaceOriginX
        coordinateSpaceOriginY = initialScreenshot.coordinateSpaceOriginY
        selectedDisplayCoordinateSpaceWidthPx = initialScreenshot.coordinateSpaceWidthPx
        selectedDisplayCoordinateSpaceHeightPx = initialScreenshot.coordinateSpaceHeightPx
        selectedDisplayCoordinateSpaceOriginX = initialScreenshot.coordinateSpaceOriginX
        selectedDisplayCoordinateSpaceOriginY = initialScreenshot.coordinateSpaceOriginY

        if initialScreenshot.width > 0, initialScreenshot.height > 0 {
            coordinateScaleX = Double(initialScreenshot.coordinateSpaceWidthPx) / Double(initialScreenshot.width)
            coordinateScaleY = Double(initialScreenshot.coordinateSpaceHeightPx) / Double(initialScreenshot.height)
        } else {
            coordinateScaleX = 1.0
            coordinateScaleY = 1.0
        }

        // Prime focus on the selected display so subsequent app launches and input stay screen-aligned.
        anchorInteractionTarget(executor: executor, reason: "run_start", performClick: true)

        recordTrace(
            kind: .info,
            "Prompt selected: name=\(promptTemplate.name) version=\(promptTemplate.config.version) model=\(promptTemplate.config.llm)."
        )
        if let sourceURL = promptTemplate.sourceURL {
            recordTrace(kind: .info, "Prompt file: \(sourceURL.path)")
        }
        if let reasoningEffort = promptTemplate.config.reasoningEffort {
            recordTrace(kind: .info, "Reasoning settings: effort=\(reasoningEffort) summary=\(promptTemplate.config.reasoningSummary ?? "none").")
        }
        recordTrace(
            kind: .info,
            "Execution started (model=\(promptTemplate.config.llm), tools=desktop_action,terminal_exec)."
        )

        let renderedPrompt = renderPrompt(promptTemplate.prompt, taskMarkdown: taskMarkdown, screenshot: initialScreenshot)
        let initialPromptText = appendVisualCoordinateContext(to: renderedPrompt, screenshot: initialScreenshot)

        let tools = [
            desktopActionToolDefinition(),
            terminalExecToolDefinition()
        ]

        let initialInput = [
            userTextAndImageInput(
                text: initialPromptText,
                screenshot: initialScreenshot,
                source: .initialPromptImage
            )
        ]

        var response = try await transportSession.send(
            OpenAIResponsesTransportRequest(
                model: promptTemplate.config.llm,
                input: initialInput,
                tools: tools,
                previousResponseId: nil,
                reasoningEffort: promptTemplate.config.reasoningEffort,
                reasoningSummary: promptTemplate.config.reasoningSummary,
                apiKey: apiKey
            )
        )

        var executedSteps: [String] = []
        var generatedQuestions: [String] = []
        var pendingVisualVerificationStep: String?

        do {
            for turn in 1...200 {
                try Task.checkCancellation()

                recordTrace(kind: .llmResponse, summarizeResponse(turn: turn, response: response))
                let functionCalls = try extractFunctionCalls(from: response)

                if functionCalls.isEmpty {
                    let completion = parseCompletion(
                        from: extractCompletionText(from: response),
                        pendingVisualVerificationStep: pendingVisualVerificationStep
                    )
                    recordTrace(
                        kind: .completion,
                        "Completion: status=\(completion.outcome) questions=\(completion.questions.count) summary=\(completion.summary == nil ? "none" : "present")"
                    )
                    if let rawCompletionText = completion.rawCompletionText {
                        recordExactTrace(kind: .completion, "Completion payload: \(rawCompletionText)")
                    }
                    return AutomationRunResult(
                        outcome: completion.outcome,
                        executedSteps: executedSteps,
                        generatedQuestions: dedupe(generatedQuestions + completion.questions),
                        errorMessage: completion.errorMessage,
                        llmSummary: composeLLMSummary(from: completion)
                    )
                }

                var followupInput: [[String: Any]] = []
                var pendingFollowupVision: OpenAIFollowupVisionStrategy?
                for functionCall in functionCalls {
                    try Task.checkCancellation()
                    recordTrace(kind: .toolUse, summarizeFunctionCall(functionCall))

                    let execution = try await executeFunctionCall(functionCall, executor: executor)
                    if let stepDescription = execution.stepDescription {
                        executedSteps.append(stepDescription)
                        recordTrace(kind: .localAction, stepDescription)
                    } else if execution.isError {
                        recordTrace(kind: .error, execution.output)
                    }

                    generatedQuestions.append(contentsOf: execution.generatedQuestions)
                    pendingFollowupVision = execution.followupVision ?? pendingFollowupVision
                    switch execution.verificationDisposition {
                    case .noChange:
                        break
                    case .require(let stepDescription):
                        pendingVisualVerificationStep = stepDescription
                    case .clear:
                        pendingVisualVerificationStep = nil
                    }
                    followupInput.append(
                        functionCallOutputInput(callID: execution.callID, output: execution.output)
                    )
                }

                let latestScreenshot: OpenAICapturedScreenshot
                if let followupVision = pendingFollowupVision {
                    switch followupVision {
                    case .provided(let screenshot, _):
                        latestScreenshot = screenshot
                    case .currentView(let description):
                        latestScreenshot = try renderCurrentVisionViewForLLM(
                            source: .postActionSnapshot,
                            modeOverride: nil,
                            overlay: nil,
                            gridSpacing: nil,
                            zoomScale: nil
                        )
                        recordTrace(kind: .info, description)
                    case .fullDisplay(let description):
                        latestScreenshot = try captureAndApplyFullDisplayScreenshotForLLM(
                            source: .postActionSnapshot,
                            overlay: .none,
                            gridSpacing: nil
                        )
                        recordTrace(kind: .info, description)
                    }
                } else {
                    latestScreenshot = try captureAndApplyFullDisplayScreenshotForLLM(
                        source: .postActionSnapshot,
                        overlay: .none,
                        gridSpacing: nil
                    )
                }
                toolDisplayWidthPx = latestScreenshot.width
                toolDisplayHeightPx = latestScreenshot.height
                coordinateSpaceWidthPx = latestScreenshot.coordinateSpaceWidthPx
                coordinateSpaceHeightPx = latestScreenshot.coordinateSpaceHeightPx
                coordinateSpaceOriginX = latestScreenshot.coordinateSpaceOriginX
                coordinateSpaceOriginY = latestScreenshot.coordinateSpaceOriginY

                if latestScreenshot.width > 0, latestScreenshot.height > 0 {
                    coordinateScaleX = Double(latestScreenshot.coordinateSpaceWidthPx) / Double(latestScreenshot.width)
                    coordinateScaleY = Double(latestScreenshot.coordinateSpaceHeightPx) / Double(latestScreenshot.height)
                } else {
                    coordinateScaleX = 1.0
                    coordinateScaleY = 1.0
                }

                followupInput.append(
                    userTextAndImageInput(
                        text: appendVisualCoordinateContext(
                            to: "Latest desktop screenshot after tool execution.",
                            screenshot: latestScreenshot
                        ),
                        screenshot: latestScreenshot,
                        source: .postActionSnapshot
                    )
                )

                response = try await transportSession.send(
                    OpenAIResponsesTransportRequest(
                        model: promptTemplate.config.llm,
                        input: followupInput,
                        tools: tools,
                        previousResponseId: response.id,
                        reasoningEffort: promptTemplate.config.reasoningEffort,
                        reasoningSummary: promptTemplate.config.reasoningSummary,
                        apiKey: apiKey
                    )
                )
            }
        } catch is CancellationError {
            recordTrace(kind: .cancelled, "Cancelled by user.")
            return AutomationRunResult(
                outcome: .cancelled,
                executedSteps: executedSteps,
                generatedQuestions: [],
                errorMessage: nil,
                llmSummary: "Cancelled by user."
            )
        }

        return AutomationRunResult(
            outcome: .needsClarification,
            executedSteps: executedSteps,
            generatedQuestions: dedupe(generatedQuestions + ["Execution loop exceeded safe iteration limit. How should I proceed?"]),
            errorMessage: "Execution loop did not converge.",
            llmSummary: nil
        )
    }
}
