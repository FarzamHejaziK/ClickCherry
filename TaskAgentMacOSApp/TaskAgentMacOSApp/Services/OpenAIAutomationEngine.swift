import Foundation
import AppKit
import ApplicationServices

enum OpenAIExecutionPlannerError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case failedToReadAPIKey
    case failedToLoadPrompt(String)
    case invalidResponse
    case requestFailed(String)
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

    private struct ParsedFunctionCall {
        var callID: String
        var name: String
        var arguments: String
    }

    private struct ToolExecutionResult {
        var callID: String
        var output: String
        var isError: Bool
        var stepDescription: String?
        var generatedQuestions: [String]
    }

    private struct CompletionResult {
        var outcome: AutomationRunOutcome
        var summary: String?
        var questions: [String]
        var errorMessage: String?
    }

    private struct TerminalExecToolResultPayload: Encodable {
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

    private struct TerminalCommandExecutionResult {
        var exitCode: Int32
        var timedOut: Bool
        var stdout: Data
        var stderr: Data
        var truncated: Bool
    }

    private final class PipeCollector {
        private let lock = NSLock()
        private let maxBytes: Int
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

    private static let terminalExecMaxCapturedOutputBytes = 64 * 1024
    private static let terminalExecDefaultTimeoutSeconds = 30.0
    private static let terminalExecMaxTimeoutSeconds = 120.0
    private static let terminalExecAlwaysVisualExecutables: Set<String> = [
        "osascript",
        "cliclick"
    ]
    private static let terminalExecVisualCommandKeywords: [String] = [
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

    private let apiKeyStore: any APIKeyStore
    private let promptCatalog: PromptCatalogService
    private let promptName: String
    private let session: URLSession
    private let transportRetryPolicy: TransportRetryPolicy
    private let sleepNanoseconds: @Sendable (UInt64) async -> Void
    private let screenshotProvider: () throws -> OpenAICapturedScreenshot
    private let cursorPositionProvider: () -> (x: Int, y: Int)?
    private let screenshotLogSink: ((LLMScreenshotLogEntry) -> Void)?
    private let callLogSink: ((LLMCallLogEntry) -> Void)?
    private let traceSink: ((ExecutionTraceEntry) -> Void)?

    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()

    private var coordinateScaleX: Double = 1.0
    private var coordinateScaleY: Double = 1.0
    private var toolDisplayWidthPx: Int = 0
    private var toolDisplayHeightPx: Int = 0
    private var coordinateSpaceWidthPx: Int = 0
    private var coordinateSpaceHeightPx: Int = 0

    init(
        apiKeyStore: any APIKeyStore,
        promptCatalog: PromptCatalogService = PromptCatalogService(),
        promptName: String = "execution_agent_openai",
        callLogSink: ((LLMCallLogEntry) -> Void)? = nil,
        screenshotLogSink: ((LLMScreenshotLogEntry) -> Void)? = nil,
        traceSink: ((ExecutionTraceEntry) -> Void)? = nil,
        session: URLSession = .shared,
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
        self.screenshotLogSink = screenshotLogSink
        self.traceSink = traceSink
        self.session = session
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

        let initialScreenshot: OpenAICapturedScreenshot
        do {
            initialScreenshot = try captureScreenshotForLLM(source: .initialPromptImage)
        } catch {
            throw OpenAIExecutionPlannerError.screenshotCaptureFailed
        }

        toolDisplayWidthPx = initialScreenshot.width
        toolDisplayHeightPx = initialScreenshot.height
        coordinateSpaceWidthPx = initialScreenshot.coordinateSpaceWidthPx
        coordinateSpaceHeightPx = initialScreenshot.coordinateSpaceHeightPx

        if initialScreenshot.width > 0, initialScreenshot.height > 0 {
            coordinateScaleX = Double(initialScreenshot.coordinateSpaceWidthPx) / Double(initialScreenshot.width)
            coordinateScaleY = Double(initialScreenshot.coordinateSpaceHeightPx) / Double(initialScreenshot.height)
        } else {
            coordinateScaleX = 1.0
            coordinateScaleY = 1.0
        }

        recordTrace(kind: .info, "Execution started (model=\(promptTemplate.config.llm), tools=desktop_action,terminal_exec).")
        recordTrace(
            kind: .info,
            "Captured initial screenshot (\(initialScreenshot.width)x\(initialScreenshot.height), \(initialScreenshot.mediaType), raw=\(initialScreenshot.byteCount) bytes, base64=\(initialScreenshot.base64Data.utf8.count) bytes; capture=\(initialScreenshot.captureWidthPx)x\(initialScreenshot.captureHeightPx) coordSpace=\(initialScreenshot.coordinateSpaceWidthPx)x\(initialScreenshot.coordinateSpaceHeightPx))."
        )

        let renderedPrompt = renderPrompt(
            promptTemplate.prompt,
            taskMarkdown: taskMarkdown,
            screenWidth: initialScreenshot.width,
            screenHeight: initialScreenshot.height
        )

        let tools = [
            desktopActionToolDefinition(),
            terminalExecToolDefinition()
        ]

        let initialInput = [
            userTextAndImageInput(
                text: renderedPrompt,
                screenshot: initialScreenshot
            )
        ]

        var response = try await sendResponsesRequest(
            model: promptTemplate.config.llm,
            input: initialInput,
            tools: tools,
            previousResponseId: nil,
            apiKey: apiKey
        )

        var executedSteps: [String] = []
        var generatedQuestions: [String] = []

        do {
            for turn in 1...200 {
                try Task.checkCancellation()

                recordTrace(kind: .llmResponse, summarizeResponse(turn: turn, response: response))
                let functionCalls = try extractFunctionCalls(from: response)

                if functionCalls.isEmpty {
                    let completion = parseCompletion(from: extractCompletionText(from: response))
                    recordTrace(
                        kind: .completion,
                        "Completion: status=\(completion.outcome) questions=\(completion.questions.count) summary=\(completion.summary == nil ? "none" : "present")"
                    )
                    return AutomationRunResult(
                        outcome: completion.outcome,
                        executedSteps: executedSteps,
                        generatedQuestions: dedupe(generatedQuestions + completion.questions),
                        errorMessage: completion.errorMessage,
                        llmSummary: completion.summary
                    )
                }

                var followupInput: [[String: Any]] = []
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
                    followupInput.append(
                        functionCallOutputInput(callID: execution.callID, output: execution.output)
                    )
                }

                let latestScreenshot = try captureScreenshotForLLM(source: .postActionSnapshot)
                followupInput.append(
                    userTextAndImageInput(
                        text: "Latest desktop screenshot after tool execution.",
                        screenshot: latestScreenshot
                    )
                )

                response = try await sendResponsesRequest(
                    model: promptTemplate.config.llm,
                    input: followupInput,
                    tools: tools,
                    previousResponseId: response.id,
                    apiKey: apiKey
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

    private func sendResponsesRequest(
        model: String,
        input: [[String: Any]],
        tools: [[String: Any]],
        previousResponseId: String?,
        apiKey: String
    ) async throws -> OpenAIResponsesResponse {
        var requestBody: [String: Any] = [
            "model": model,
            "input": input,
            "tools": tools,
            "tool_choice": "auto",
            "truncation": "auto"
        ]
        if let previousResponseId, !previousResponseId.isEmpty {
            requestBody["previous_response_id"] = previousResponseId
        }

        let encodedRequest: Data
        do {
            encodedRequest = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw OpenAIExecutionPlannerError.invalidResponse
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = encodedRequest

        let bytesSent = request.httpBody?.count
        let urlString = request.url?.absoluteString ?? "unknown"

        let pair: (data: Data, response: URLResponse, attempt: Int, attemptStartedAt: Date)
        let response: HTTPURLResponse
        let data: Data
        let attempt: Int
        let attemptStartedAt: Date
        do {
            pair = try await dataWithRetry(for: request)
            guard let http = pair.response as? HTTPURLResponse else {
                recordCall(
                    startedAt: pair.attemptStartedAt,
                    finishedAt: Date(),
                    attempt: pair.attempt,
                    url: urlString,
                    httpStatus: nil,
                    requestId: nil,
                    bytesSent: bytesSent,
                    bytesReceived: pair.data.count,
                    outcome: .failure,
                    message: "Non-HTTP response."
                )
                throw OpenAIExecutionPlannerError.invalidResponse
            }
            response = http
            data = pair.data
            attempt = pair.attempt
            attemptStartedAt = pair.attemptStartedAt
        } catch let error as OpenAIExecutionPlannerError {
            throw error
        } catch {
            if isCancellation(error) {
                throw CancellationError()
            }
            throw OpenAIExecutionPlannerError.requestFailed(describeTransportError(error))
        }

        guard (200..<300).contains(response.statusCode) else {
            let message = serverMessage(from: data, statusCode: response.statusCode)
            recordCall(
                startedAt: attemptStartedAt,
                finishedAt: Date(),
                attempt: attempt,
                url: urlString,
                httpStatus: response.statusCode,
                requestId: headerValue(response, name: "x-request-id"),
                bytesSent: bytesSent,
                bytesReceived: data.count,
                outcome: .failure,
                message: message
            )
            throw OpenAIExecutionPlannerError.requestFailed(message)
        }

        guard let payload = try? jsonDecoder.decode(OpenAIResponsesResponse.self, from: data) else {
            recordCall(
                startedAt: attemptStartedAt,
                finishedAt: Date(),
                attempt: attempt,
                url: urlString,
                httpStatus: response.statusCode,
                requestId: headerValue(response, name: "x-request-id"),
                bytesSent: bytesSent,
                bytesReceived: data.count,
                outcome: .failure,
                message: "Failed to decode OpenAI response JSON."
            )
            throw OpenAIExecutionPlannerError.invalidResponse
        }

        let hasOutputItems = !(payload.output ?? []).isEmpty
        let hasOutputText = !(payload.outputText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        guard hasOutputItems || hasOutputText else {
            throw OpenAIExecutionPlannerError.invalidToolLoopResponse
        }

        recordCall(
            startedAt: attemptStartedAt,
            finishedAt: Date(),
            attempt: attempt,
            url: urlString,
            httpStatus: response.statusCode,
            requestId: headerValue(response, name: "x-request-id"),
            bytesSent: bytesSent,
            bytesReceived: data.count,
            outcome: .success,
            message: nil
        )
        return payload
    }

    private func dataWithRetry(for request: URLRequest) async throws -> (data: Data, response: URLResponse, attempt: Int, attemptStartedAt: Date) {
        let maxAttempts = max(1, transportRetryPolicy.maxAttempts)
        for attempt in 1...maxAttempts {
            let startedAt = Date()
            do {
                let pair = try await session.data(for: request)
                return (pair.0, pair.1, attempt, startedAt)
            } catch {
                if isCancellation(error) {
                    recordCall(
                        startedAt: startedAt,
                        finishedAt: Date(),
                        attempt: attempt,
                        url: request.url?.absoluteString ?? "unknown",
                        httpStatus: nil,
                        requestId: nil,
                        bytesSent: request.httpBody?.count,
                        bytesReceived: nil,
                        outcome: .failure,
                        message: "Cancelled."
                    )
                    throw CancellationError()
                }

                recordCall(
                    startedAt: startedAt,
                    finishedAt: Date(),
                    attempt: attempt,
                    url: request.url?.absoluteString ?? "unknown",
                    httpStatus: nil,
                    requestId: nil,
                    bytesSent: request.httpBody?.count,
                    bytesReceived: nil,
                    outcome: .failure,
                    message: describeTransportError(error)
                )

                if attempt < maxAttempts, shouldRetryTransportError(error) {
                    let delaySeconds = computeRetryDelaySeconds(attempt: attempt)
                    recordTrace(
                        kind: .info,
                        "Retrying OpenAI request after transport error (attempt \(attempt + 1)/\(maxAttempts)) after \(String(format: "%.2f", delaySeconds))s."
                    )
                    await sleepNanoseconds(UInt64(max(0.0, delaySeconds) * 1_000_000_000))
                    continue
                }
                throw error
            }
        }

        throw URLError(.unknown)
    }

    private func computeRetryDelaySeconds(attempt: Int) -> Double {
        let base = max(0.0, transportRetryPolicy.baseDelaySeconds)
        let maxDelay = max(0.0, transportRetryPolicy.maxDelaySeconds)
        let exponent = max(0.0, Double(attempt - 1))
        let delay = base * pow(2.0, exponent)
        return min(delay, maxDelay)
    }

    private func shouldRetryTransportError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return false
        }

        switch nsError.code {
        case URLError.secureConnectionFailed.rawValue,
             URLError.networkConnectionLost.rawValue,
             URLError.timedOut.rawValue,
             URLError.cannotConnectToHost.rawValue,
             URLError.cannotFindHost.rawValue,
             URLError.dnsLookupFailed.rawValue,
             URLError.notConnectedToInternet.rawValue:
            return true
        default:
            return false
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == URLError.cancelled.rawValue
    }

    private func recordCall(
        startedAt: Date,
        finishedAt: Date,
        attempt: Int,
        url: String,
        httpStatus: Int?,
        requestId: String?,
        bytesSent: Int?,
        bytesReceived: Int?,
        outcome: LLMCallOutcome,
        message: String?
    ) {
        callLogSink?(
            LLMCallLogEntry(
                startedAt: startedAt,
                finishedAt: finishedAt,
                provider: .openAI,
                operation: .execution,
                attempt: attempt,
                url: url,
                httpStatus: httpStatus,
                requestId: requestId,
                bytesSent: bytesSent,
                bytesReceived: bytesReceived,
                outcome: outcome,
                message: message
            )
        )
    }

    private func headerValue(_ response: HTTPURLResponse, name: String) -> String? {
        for (keyAny, valueAny) in response.allHeaderFields {
            guard let key = keyAny as? String else { continue }
            if key.lowercased() == name.lowercased() {
                if let value = valueAny as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
                return "\(valueAny)"
            }
        }
        return nil
    }

    private func describeTransportError(_ error: Error) -> String {
        let nsError = error as NSError
        var components: [String] = []

        components.append("\(nsError.localizedDescription) (domain=\(nsError.domain) code=\(nsError.code))")
        if let failingURL = (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL) {
            components.append("url=\(failingURL.absoluteString)")
        }

        var depth = 0
        var underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        while let underlyingError = underlying, depth < 3 {
            components.append(
                "underlying=\(underlyingError.localizedDescription) (domain=\(underlyingError.domain) code=\(underlyingError.code))"
            )
            underlying = underlyingError.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }

        if nsError.domain == NSURLErrorDomain, nsError.code == URLError.secureConnectionFailed.rawValue {
            components.append(
                "hint=TLS handshake failed (-1200). Common causes: VPN/proxy TLS inspection, captive portals, missing/blocked trust roots, or incorrect system clock."
            )
        }

        return components.joined(separator: " | ")
    }

    private func extractFunctionCalls(from response: OpenAIResponsesResponse) throws -> [ParsedFunctionCall] {
        guard let output = response.output else { return [] }

        var calls: [ParsedFunctionCall] = []
        for item in output where item.type == "function_call" {
            guard let callID = (item.callID ?? item.id)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !callID.isEmpty else {
                throw OpenAIExecutionPlannerError.invalidToolLoopResponse
            }
            guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                throw OpenAIExecutionPlannerError.invalidToolLoopResponse
            }
            guard let arguments = item.arguments?.jsonString(using: jsonEncoder) else {
                throw OpenAIExecutionPlannerError.invalidToolLoopResponse
            }
            calls.append(ParsedFunctionCall(callID: callID, name: name, arguments: arguments))
        }
        return calls
    }

    private func executeFunctionCall(
        _ functionCall: ParsedFunctionCall,
        executor: any DesktopActionExecutor
    ) async throws -> ToolExecutionResult {
        let toolName = functionCall.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard toolName == "desktop_action" || toolName == "terminal_exec" else {
            return ToolExecutionResult(
                callID: functionCall.callID,
                output: makeToolOutput(
                    ok: false,
                    message: "Unsupported tool '\(functionCall.name)'.",
                    error: "unsupported_tool"
                ),
                isError: true,
                stepDescription: nil,
                generatedQuestions: ["Model requested unsupported tool '\(functionCall.name)'. What should I do?"]
            )
        }

        guard
            let argumentsData = functionCall.arguments.data(using: .utf8),
            let object = try? jsonDecoder.decode([String: OpenAIJSONValue].self, from: argumentsData)
        else {
            return ToolExecutionResult(
                callID: functionCall.callID,
                output: makeToolOutput(
                    ok: false,
                    message: "Tool input was invalid JSON.",
                    error: "invalid_input"
                ),
                isError: true,
                stepDescription: nil,
                generatedQuestions: ["Execution input from model was invalid. How should I proceed?"]
            )
        }

        if toolName == "terminal_exec" {
            return await executeTerminalExecFunctionCall(callID: functionCall.callID, input: object)
        }

        let action = (object["action"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !action.isEmpty else {
            return ToolExecutionResult(
                callID: functionCall.callID,
                output: makeToolOutput(
                    ok: false,
                    message: "Tool input missing 'action'.",
                    error: "missing_action"
                ),
                isError: true,
                stepDescription: nil,
                generatedQuestions: ["Model omitted the requested action. What should I do?"]
            )
        }

        do {
            switch action {
            case "screenshot":
                return ToolExecutionResult(
                    callID: functionCall.callID,
                    output: makeToolOutput(ok: true, message: "Captured screenshot."),
                    isError: false,
                    stepDescription: "Capture screenshot",
                    generatedQuestions: []
                )
            case "cursor_position", "get_cursor_position", "mouse_position":
                guard let cursor = cursorPositionProvider() else {
                    return ToolExecutionResult(
                        callID: functionCall.callID,
                        output: makeToolOutput(ok: false, message: "Failed to read current cursor position.", error: "cursor_unavailable"),
                        isError: true,
                        stepDescription: nil,
                        generatedQuestions: ["Action '\(action)' failed because cursor position could not be read. What should I do instead?"]
                    )
                }
                let mapped = mapToToolCoordinates(x: cursor.x, y: cursor.y)
                let payload = makeToolOutput(
                    ok: true,
                    message: "Cursor position",
                    data: ["x": mapped.x, "y": mapped.y]
                )
                return ToolExecutionResult(
                    callID: functionCall.callID,
                    output: payload,
                    isError: false,
                    stepDescription: "Read cursor position (\(mapped.x), \(mapped.y))",
                    generatedQuestions: []
                )
            case "mouse_move", "move_mouse", "move":
                guard let (x, y) = extractPoint(from: object) else {
                    return invalidInputResult(callID: functionCall.callID, action: action)
                }
                let mapped = mapToScreenCoordinates(x: x, y: y)
                try executor.moveMouse(x: mapped.x, y: mapped.y)
                return successResult(callID: functionCall.callID, stepDescription: "Move mouse to (\(mapped.x), \(mapped.y))")
            case "left_click":
                guard let (x, y) = extractPoint(from: object) else {
                    return invalidInputResult(callID: functionCall.callID, action: action)
                }
                let mapped = mapToScreenCoordinates(x: x, y: y)
                try executor.click(x: mapped.x, y: mapped.y)
                return successResult(callID: functionCall.callID, stepDescription: "Click at (\(mapped.x), \(mapped.y))")
            case "right_click":
                guard let (x, y) = extractPoint(from: object) else {
                    return invalidInputResult(callID: functionCall.callID, action: action)
                }
                let mapped = mapToScreenCoordinates(x: x, y: y)
                try executor.rightClick(x: mapped.x, y: mapped.y)
                return successResult(callID: functionCall.callID, stepDescription: "Right click at (\(mapped.x), \(mapped.y))")
            case "double_click":
                guard let (x, y) = extractPoint(from: object) else {
                    return invalidInputResult(callID: functionCall.callID, action: action)
                }
                let mapped = mapToScreenCoordinates(x: x, y: y)
                try executor.click(x: mapped.x, y: mapped.y)
                try executor.click(x: mapped.x, y: mapped.y)
                return successResult(callID: functionCall.callID, stepDescription: "Double click at (\(mapped.x), \(mapped.y))")
            case "type":
                guard let text = object["text"]?.stringValue,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return invalidInputResult(callID: functionCall.callID, action: action)
                }
                recordTrace(kind: .info, "Typing uses clipboard paste (cmd+v) with clipboard restore for reliability.")
                try executor.typeText(text)
                return successResult(callID: functionCall.callID, stepDescription: "Type text '\(text)'")
            case "key":
                guard let raw = firstStringValue(from: object, keys: ["key", "text", "keys"]),
                      let shortcut = parseShortcut(raw) else {
                    return invalidInputResult(callID: functionCall.callID, action: action)
                }
                try executor.sendShortcut(
                    key: shortcut.key,
                    command: shortcut.command,
                    option: shortcut.option,
                    control: shortcut.control,
                    shift: shortcut.shift
                )
                return successResult(callID: functionCall.callID, stepDescription: "Press shortcut '\(raw)'")
            case "open_app":
                guard let appName = firstStringValue(from: object, keys: ["app", "name"]) else {
                    return invalidInputResult(callID: functionCall.callID, action: action)
                }
                try executor.openApp(named: appName)
                return successResult(callID: functionCall.callID, stepDescription: "Open app '\(appName)'")
            case "open_url":
                guard let urlRaw = firstStringValue(from: object, keys: ["url"]),
                      let url = URL(string: urlRaw) else {
                    return invalidInputResult(callID: functionCall.callID, action: action)
                }
                try executor.openURL(url)
                return successResult(callID: functionCall.callID, stepDescription: "Open URL '\(url.absoluteString)'")
            case "scroll":
                if let (x, y) = extractPoint(from: object) {
                    let mapped = mapToScreenCoordinates(x: x, y: y)
                    try executor.moveMouse(x: mapped.x, y: mapped.y)
                }
                guard let (dx, dy) = extractScrollDelta(from: object) else {
                    return invalidInputResult(callID: functionCall.callID, action: action)
                }
                try executor.scroll(deltaX: dx, deltaY: dy)
                return successResult(callID: functionCall.callID, stepDescription: "Scroll (\(dx), \(dy))")
            case "wait":
                let seconds = max(0.1, object["seconds"]?.doubleValue ?? object["duration"]?.doubleValue ?? 0.5)
                await sleepNanoseconds(UInt64(seconds * 1_000_000_000))
                return successResult(callID: functionCall.callID, stepDescription: "Wait \(String(format: "%.1f", seconds))s")
            default:
                return ToolExecutionResult(
                    callID: functionCall.callID,
                    output: makeToolOutput(
                        ok: false,
                        message: "Unsupported action '\(action)'.",
                        error: "unsupported_action"
                    ),
                    isError: true,
                    stepDescription: nil,
                    generatedQuestions: ["Action '\(action)' is unsupported. What should I do instead?"]
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return ToolExecutionResult(
                callID: functionCall.callID,
                output: makeToolOutput(
                    ok: false,
                    message: "Action '\(action)' failed: \(error.localizedDescription)",
                    error: "execution_failed"
                ),
                isError: true,
                stepDescription: nil,
                generatedQuestions: ["Execution failed for action '\(action)'. What should I do instead?"]
            )
        }
    }

    private func successResult(callID: String, stepDescription: String) -> ToolExecutionResult {
        ToolExecutionResult(
            callID: callID,
            output: makeToolOutput(ok: true, message: "Done"),
            isError: false,
            stepDescription: stepDescription,
            generatedQuestions: []
        )
    }

    private func invalidInputResult(callID: String, action: String) -> ToolExecutionResult {
        ToolExecutionResult(
            callID: callID,
            output: makeToolOutput(
                ok: false,
                message: "Action '\(action)' had invalid input.",
                error: "invalid_input"
            ),
            isError: true,
            stepDescription: nil,
            generatedQuestions: ["Action '\(action)' had invalid input from the model. How should I proceed?"]
        )
    }

    private func executeTerminalExecFunctionCall(
        callID: String,
        input: [String: OpenAIJSONValue]
    ) async -> ToolExecutionResult {
        guard let executableRaw = input["executable"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !executableRaw.isEmpty else {
            return ToolExecutionResult(
                callID: callID,
                output: makeToolOutput(ok: false, message: "Terminal tool input missing 'executable'.", error: "invalid_input"),
                isError: true,
                stepDescription: nil,
                generatedQuestions: ["Model omitted the terminal executable to run. What should I do?"]
            )
        }

        var args: [String] = []
        if let argsValue = input["args"] {
            guard let array = argsValue.arrayValue else {
                return ToolExecutionResult(
                    callID: callID,
                    output: makeToolOutput(ok: false, message: "Terminal tool input field 'args' must be an array of strings.", error: "invalid_input"),
                    isError: true,
                    stepDescription: nil,
                    generatedQuestions: ["Terminal tool input field 'args' was invalid. What should I do?"]
                )
            }
            for value in array {
                guard let s = value.stringValue else {
                    return ToolExecutionResult(
                        callID: callID,
                        output: makeToolOutput(ok: false, message: "Terminal tool input field 'args' must contain only strings.", error: "invalid_input"),
                        isError: true,
                        stepDescription: nil,
                        generatedQuestions: ["Terminal tool input field 'args' was invalid. What should I do?"]
                    )
                }
                args.append(s)
            }
        }

        let timeoutRaw = input["timeout_seconds"]?.doubleValue ?? Self.terminalExecDefaultTimeoutSeconds
        let timeoutSeconds = min(Self.terminalExecMaxTimeoutSeconds, max(0.1, timeoutRaw))

        if let policyViolationMessage = validateTerminalExecPolicy(executable: executableRaw, args: args) {
            return ToolExecutionResult(
                callID: callID,
                output: makeToolOutput(ok: false, message: policyViolationMessage, error: "policy_violation"),
                isError: true,
                stepDescription: nil,
                generatedQuestions: []
            )
        }

        guard let resolvedExecutable = resolveTerminalExecutable(executableRaw) else {
            return ToolExecutionResult(
                callID: callID,
                output: makeToolOutput(
                    ok: false,
                    message: "Executable '\(executableRaw)' was not found or is not executable.",
                    error: "executable_not_found"
                ),
                isError: true,
                stepDescription: nil,
                generatedQuestions: ["Terminal command executable was not found ('\(executableRaw)'). What should I do instead?"]
            )
        }

        let commandSummary = summarizeTerminalCommand(executablePath: resolvedExecutable, args: args)
        recordTrace(kind: .info, "Terminal exec requested: \(commandSummary)")

        do {
            let exec = try await runTerminalCommand(executablePath: resolvedExecutable, args: args, timeoutSeconds: timeoutSeconds)
            let stdout = String(decoding: exec.stdout, as: UTF8.self)
            let stderr = String(decoding: exec.stderr, as: UTF8.self)

            let payload = TerminalExecToolResultPayload(
                ok: (exec.exitCode == 0) && !exec.timedOut,
                exitCode: Int(exec.exitCode),
                timedOut: exec.timedOut,
                stdout: stdout,
                stderr: stderr,
                truncated: exec.truncated
            )

            let payloadText: String
            if let json = try? String(data: jsonEncoder.encode(payload), encoding: .utf8) {
                payloadText = json
            } else {
                payloadText = "{\"ok\":false,\"exit_code\":-1,\"timed_out\":false,\"stdout\":\"\",\"stderr\":\"Failed to encode terminal tool result.\",\"truncated\":false}"
            }

            return ToolExecutionResult(
                callID: callID,
                output: payloadText,
                isError: !payload.ok,
                stepDescription: "Terminal exec: \(commandSummary)",
                generatedQuestions: payload.ok ? [] : ["Terminal command failed (\(commandSummary)). What should I do instead?"]
            )
        } catch {
            return ToolExecutionResult(
                callID: callID,
                output: makeToolOutput(ok: false, message: "Terminal exec failed: \(error.localizedDescription)", error: "execution_failed"),
                isError: true,
                stepDescription: nil,
                generatedQuestions: ["Terminal exec failed for (\(commandSummary)). What should I do instead?"]
            )
        }
    }

    private func resolveTerminalExecutable(_ raw: String) -> String? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        if cleaned.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: cleaned) ? cleaned : nil
        }

        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for directory in pathEnv.split(separator: ":").map(String.init) {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(cleaned, isDirectory: false)
                .path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private func validateTerminalExecPolicy(executable: String, args: [String]) -> String? {
        let executableName = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
        let commandLineLower = ([executableName] + args).joined(separator: " ").lowercased()

        if Self.terminalExecAlwaysVisualExecutables.contains(executableName) {
            return "Terminal command '\(executableName)' is blocked for UI/visual automation. Use tool 'desktop_action' for on-screen actions (find/hover/click/scroll/type based on screenshots)."
        }

        if Self.terminalExecVisualCommandKeywords.contains(where: { commandLineLower.contains($0) }) {
            return "Terminal command appears to target visual UI state. Use tool 'desktop_action' for on-screen actions and coordinates."
        }

        return nil
    }

    private func summarizeTerminalCommand(executablePath: String, args: [String]) -> String {
        let cmd = ([URL(fileURLWithPath: executablePath).lastPathComponent] + args).joined(separator: " ")
        return truncate(cmd, limit: 220)
    }

    private func runTerminalCommand(
        executablePath: String,
        args: [String],
        timeoutSeconds: Double
    ) async throws -> TerminalCommandExecutionResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let result = try self.runTerminalCommandSync(
                        executablePath: executablePath,
                        args: args,
                        timeoutSeconds: timeoutSeconds
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runTerminalCommandSync(
        executablePath: String,
        args: [String],
        timeoutSeconds: Double
    ) throws -> TerminalCommandExecutionResult {
        let exeURL = URL(fileURLWithPath: executablePath)

        let process = Process()
        process.executableURL = exeURL
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutCollector = PipeCollector(maxBytes: Self.terminalExecMaxCapturedOutputBytes)
        let stderrCollector = PipeCollector(maxBytes: Self.terminalExecMaxCapturedOutputBytes)

        let terminationSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            terminationSemaphore.signal()
        }

        try process.run()

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let handle = stdoutPipe.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                stdoutCollector.append(chunk)
            }
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let handle = stderrPipe.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                stderrCollector.append(chunk)
            }
            group.leave()
        }

        var timedOut = false
        if terminationSemaphore.wait(timeout: .now() + max(0.1, timeoutSeconds)) != .success {
            timedOut = true
            if process.isRunning {
                process.terminate()
            }
            _ = terminationSemaphore.wait(timeout: .now() + 2.0)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = terminationSemaphore.wait(timeout: .now() + 1.0)
            }
        }

        group.wait()

        let truncated = stdoutCollector.truncated || stderrCollector.truncated
        return TerminalCommandExecutionResult(
            exitCode: process.terminationStatus,
            timedOut: timedOut,
            stdout: stdoutCollector.snapshot(),
            stderr: stderrCollector.snapshot(),
            truncated: truncated
        )
    }

    private func mapToToolCoordinates(x: Int, y: Int) -> (x: Int, y: Int) {
        let invScaleX = coordinateScaleX == 0 ? 1.0 : coordinateScaleX
        let invScaleY = coordinateScaleY == 0 ? 1.0 : coordinateScaleY
        let scaledX = Int((Double(x) / invScaleX).rounded())
        let scaledY = Int((Double(y) / invScaleY).rounded())

        if toolDisplayWidthPx > 0, toolDisplayHeightPx > 0 {
            return (
                max(0, min(toolDisplayWidthPx - 1, scaledX)),
                max(0, min(toolDisplayHeightPx - 1, scaledY))
            )
        }

        return (scaledX, scaledY)
    }

    private func mapToScreenCoordinates(x: Int, y: Int) -> (x: Int, y: Int) {
        let scaledX = Int((Double(x) * coordinateScaleX).rounded())
        let scaledY = Int((Double(y) * coordinateScaleY).rounded())

        if coordinateSpaceWidthPx > 0, coordinateSpaceHeightPx > 0 {
            let clampedX = max(0, min(coordinateSpaceWidthPx - 1, scaledX))
            let clampedY = max(0, min(coordinateSpaceHeightPx - 1, scaledY))
            if clampedX != scaledX || clampedY != scaledY {
                recordTrace(
                    kind: .info,
                    "Clamped tool coordinates from (\(scaledX), \(scaledY)) to (\(clampedX), \(clampedY)) for coordSpace=\(coordinateSpaceWidthPx)x\(coordinateSpaceHeightPx)."
                )
            }
            return (clampedX, clampedY)
        }

        return (scaledX, scaledY)
    }

    private func firstStringValue(from object: [String: OpenAIJSONValue], keys: [String]) -> String? {
        for key in keys {
            guard let value = object[key]?.stringValue else {
                continue
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private func parseShortcut(_ raw: String) -> (key: String, command: Bool, option: Bool, control: Bool, shift: Bool)? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        let pieces = normalized
            .split(separator: "+")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        var command = false
        var option = false
        var control = false
        var shift = false
        var key: String?

        for piece in pieces {
            switch piece {
            case "cmd", "command", "super", "win", "windows", "meta", "⌘":
                command = true
            case "opt", "option", "alt", "⌥":
                option = true
            case "ctrl", "control", "⌃":
                control = true
            case "shift", "⇧":
                shift = true
            case "enter":
                key = "return"
            case "space", "spacebar":
                key = " "
            case "esc":
                key = "escape"
            default:
                key = piece
            }
        }

        if key == nil, !pieces.isEmpty {
            key = pieces.last
        }

        guard let resolvedKey = key else { return nil }
        return (resolvedKey, command, option, control, shift)
    }

    private func extractScrollDelta(from object: [String: OpenAIJSONValue]) -> (Int, Int)? {
        let dx = object["delta_x"]?.intValue ?? object["scroll_x"]?.intValue ?? object["dx"]?.intValue
        let dy = object["delta_y"]?.intValue ?? object["scroll_y"]?.intValue ?? object["dy"]?.intValue

        if let dx, let dy {
            return (dx, dy)
        }
        if let dy {
            return (0, dy)
        }
        if let dx {
            return (dx, 0)
        }

        if let direction = object["direction"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           let amountRaw = object["amount"]?.doubleValue ?? object["scroll_amount"]?.doubleValue ?? object["pixels"]?.doubleValue {
            let amount = Int(amountRaw.rounded())
            switch direction {
            case "down":
                return (0, -abs(amount))
            case "up":
                return (0, abs(amount))
            case "left":
                return (-abs(amount), 0)
            case "right":
                return (abs(amount), 0)
            default:
                break
            }
        }

        return nil
    }

    private func extractPoint(from object: [String: OpenAIJSONValue]) -> (Int, Int)? {
        if let x = object["x"]?.intValue, let y = object["y"]?.intValue {
            return (x, y)
        }

        for key in ["coordinate", "coordinates", "position", "point", "location", "pos"] {
            guard let value = object[key] else { continue }
            if let point = extractPoint(from: value) {
                return point
            }
        }

        return nil
    }

    private func extractPoint(from value: OpenAIJSONValue) -> (Int, Int)? {
        if let array = value.arrayValue, array.count >= 2, let x = array[0].intValue, let y = array[1].intValue {
            return (x, y)
        }

        if let obj = value.objectValue {
            let x = obj["x"]?.intValue ?? obj["left"]?.intValue
            let y = obj["y"]?.intValue ?? obj["top"]?.intValue
            if let x, let y {
                return (x, y)
            }
        }

        return nil
    }

    private func makeToolOutput(ok: Bool, message: String, data: [String: Any] = [:], error: String? = nil) -> String {
        var payload: [String: Any] = [
            "ok": ok,
            "message": message
        ]
        for (key, value) in data {
            payload[key] = value
        }
        if let error {
            payload["error"] = error
        }

        guard let encoded = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: encoded, encoding: .utf8) else {
            return "{\"ok\":false,\"message\":\"Failed to encode tool output.\",\"error\":\"encode_failed\"}"
        }
        return string
    }

    private func userTextAndImageInput(text: String, screenshot: OpenAICapturedScreenshot) -> [String: Any] {
        [
            "role": "user",
            "content": [
                [
                    "type": "input_text",
                    "text": text
                ],
                [
                    "type": "input_image",
                    "image_url": imageDataURL(for: screenshot)
                ]
            ]
        ]
    }

    private func functionCallOutputInput(callID: String, output: String) -> [String: Any] {
        [
            "type": "function_call_output",
            "call_id": callID,
            "output": output
        ]
    }

    private func imageDataURL(for screenshot: OpenAICapturedScreenshot) -> String {
        "data:\(screenshot.mediaType);base64,\(screenshot.base64Data)"
    }

    private func desktopActionToolDefinition() -> [String: Any] {
        [
            "type": "function",
            "name": "desktop_action",
            "description": "Execute one desktop action on macOS. Use this tool for click, type, key shortcuts, scrolling, app launching, URL opening, waiting, screenshots, and cursor-position reads.",
            "parameters": [
                "type": "object",
                "properties": [
                    "action": [
                        "type": "string",
                        "enum": [
                            "screenshot",
                            "cursor_position",
                            "get_cursor_position",
                            "mouse_position",
                            "mouse_move",
                            "move_mouse",
                            "move",
                            "left_click",
                            "right_click",
                            "double_click",
                            "type",
                            "key",
                            "open_app",
                            "open_url",
                            "scroll",
                            "wait"
                        ]
                    ],
                    "x": ["type": "integer"],
                    "y": ["type": "integer"],
                    "coordinate": [
                        "oneOf": [
                            [
                                "type": "array",
                                "items": ["type": "integer"],
                                "minItems": 2,
                                "maxItems": 2
                            ],
                            [
                                "type": "object",
                                "properties": [
                                    "x": ["type": "integer"],
                                    "y": ["type": "integer"],
                                    "left": ["type": "integer"],
                                    "top": ["type": "integer"]
                                ],
                                "additionalProperties": true
                            ]
                        ]
                    ],
                    "text": ["type": "string"],
                    "key": ["type": "string"],
                    "keys": ["type": "string"],
                    "app": ["type": "string"],
                    "name": ["type": "string"],
                    "url": ["type": "string"],
                    "delta_x": ["type": "integer"],
                    "delta_y": ["type": "integer"],
                    "scroll_x": ["type": "integer"],
                    "scroll_y": ["type": "integer"],
                    "direction": ["type": "string"],
                    "amount": ["type": "number"],
                    "pixels": ["type": "number"],
                    "seconds": ["type": "number"],
                    "duration": ["type": "number"]
                ],
                "required": ["action"],
                "additionalProperties": true
            ]
        ]
    }

    private func terminalExecToolDefinition() -> [String: Any] {
        [
            "type": "function",
            "name": "terminal_exec",
            "description": "Execute a terminal command and return stdout/stderr/exit_code. Use this for deterministic command-line tasks and reliable app launching.",
            "parameters": [
                "type": "object",
                "properties": [
                    "executable": [
                        "type": "string",
                        "description": "Executable name (resolved from PATH) or absolute path."
                    ],
                    "args": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Argument list."
                    ],
                    "timeout_seconds": [
                        "type": "number",
                        "description": "Optional timeout in seconds (default 30)."
                    ]
                ],
                "required": ["executable"],
                "additionalProperties": false
            ]
        ]
    }

    private func extractCompletionText(from response: OpenAIResponsesResponse) -> String {
        if let topLevel = response.outputText?.trimmingCharacters(in: .whitespacesAndNewlines), !topLevel.isEmpty {
            return topLevel
        }

        var parts: [String] = []
        for item in response.output ?? [] {
            if item.type == "message" {
                for content in item.content ?? [] {
                    guard content.type == "output_text" || content.type == "text" else { continue }
                    if let text = content.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                        parts.append(text)
                    }
                }
            } else if item.type == "output_text" || item.type == "text" {
                if let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    parts.append(text)
                }
            }
        }

        return parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseCompletion(from text: String) -> CompletionResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return CompletionResult(
                outcome: .needsClarification,
                summary: nil,
                questions: ["Execution ended without a final status. What should I do next?"],
                errorMessage: "Execution ended without a final status."
            )
        }

        if let payloadData = extractJSONPayloadData(from: trimmed),
           let payload = try? jsonDecoder.decode(OpenAIToolLoopCompletionPayload.self, from: payloadData) {
            let questions = payload.questions?.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
            return CompletionResult(
                outcome: mapStatus(payload.status),
                summary: payload.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
                questions: questions,
                errorMessage: payload.error?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return CompletionResult(
            outcome: .needsClarification,
            summary: trimmed,
            questions: ["Execution result was not machine-readable. Please clarify what should happen next."],
            errorMessage: "Final model response was not valid completion JSON."
        )
    }

    private func extractJSONPayloadData(from content: String) -> Data? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            return trimmed.data(using: .utf8)
        }

        if let fencedRange = trimmed.range(of: "```json"),
           let closingRange = trimmed.range(of: "```", range: fencedRange.upperBound..<trimmed.endIndex) {
            let payload = String(trimmed[fencedRange.upperBound..<closingRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if payload.hasPrefix("{"), payload.hasSuffix("}") {
                return payload.data(using: .utf8)
            }
        }

        guard let firstBrace = trimmed.firstIndex(of: "{"),
              let lastBrace = trimmed.lastIndex(of: "}") else {
            return nil
        }
        let payload = String(trimmed[firstBrace...lastBrace])
        return payload.data(using: .utf8)
    }

    private func resolveAPIKey() throws -> String {
        do {
            guard let raw = try apiKeyStore.readKey(for: .openAI) else {
                throw OpenAIExecutionPlannerError.missingAPIKey
            }
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                throw OpenAIExecutionPlannerError.missingAPIKey
            }
            return key
        } catch let error as OpenAIExecutionPlannerError {
            throw error
        } catch {
            throw OpenAIExecutionPlannerError.failedToReadAPIKey
        }
    }

    private func loadPromptTemplate() throws -> PromptTemplate {
        do {
            return try promptCatalog.loadPrompt(named: promptName)
        } catch {
            throw OpenAIExecutionPlannerError.failedToLoadPrompt(promptName)
        }
    }

    private func renderPrompt(_ template: String, taskMarkdown: String, screenWidth: Int, screenHeight: Int) -> String {
        template
            .replacingOccurrences(of: "{{OS_VERSION}}", with: ProcessInfo.processInfo.operatingSystemVersionString)
            .replacingOccurrences(of: "{{SCREEN_WIDTH}}", with: String(screenWidth))
            .replacingOccurrences(of: "{{SCREEN_HEIGHT}}", with: String(screenHeight))
            .replacingOccurrences(of: "{{TASK_MARKDOWN}}", with: taskMarkdown)
    }

    private func mapStatus(_ raw: String) -> AutomationRunOutcome {
        switch raw.uppercased() {
        case "SUCCESS":
            return .success
        case "FAILED":
            return .failed
        default:
            return .needsClarification
        }
    }

    private func serverMessage(from data: Data, statusCode: Int) -> String {
        if let payload = try? jsonDecoder.decode(OpenAIErrorEnvelope.self, from: data),
           let message = payload.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return message
        }
        return "HTTP \(statusCode)"
    }

    private func dedupe(_ questions: [String]) -> [String] {
        var seen: Set<String> = []
        var output: [String] = []
        for question in questions {
            let normalized = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else {
                continue
            }
            output.append(question.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    private func captureScreenshotForLLM(source: LLMScreenshotSource) throws -> OpenAICapturedScreenshot {
        let screenshot = try screenshotProvider()
        if let encodedData = Data(base64Encoded: screenshot.base64Data) {
            screenshotLogSink?(
                LLMScreenshotLogEntry(
                    source: source,
                    mediaType: screenshot.mediaType,
                    width: screenshot.width,
                    height: screenshot.height,
                    captureWidthPx: screenshot.captureWidthPx,
                    captureHeightPx: screenshot.captureHeightPx,
                    coordinateSpaceWidthPx: screenshot.coordinateSpaceWidthPx,
                    coordinateSpaceHeightPx: screenshot.coordinateSpaceHeightPx,
                    rawByteCount: screenshot.byteCount,
                    base64ByteCount: screenshot.base64Data.utf8.count,
                    imageData: encodedData
                )
            )
        }
        return screenshot
    }

    private func summarizeResponse(turn: Int, response: OpenAIResponsesResponse) -> String {
        if let output = response.output {
            let calls = output.filter { $0.type == "function_call" }
            if !calls.isEmpty {
                let summary = calls.map { call in
                    summarizeFunctionCall(
                        ParsedFunctionCall(
                            callID: call.callID ?? call.id ?? "unknown",
                            name: call.name ?? "unknown",
                            arguments: call.arguments?.jsonString(using: jsonEncoder) ?? "{}"
                        )
                    )
                }.joined(separator: " | ")
                return "Turn \(turn): function_call x\(calls.count): \(summary)"
            }
        }

        let text = extractCompletionText(from: response)
        if !text.isEmpty {
            return "Turn \(turn): text: \(truncate(text, limit: 400))"
        }

        if let output = response.output, !output.isEmpty {
            let types = output.map(\.type).joined(separator: ",")
            return "Turn \(turn): no function_call; output types: \(types)"
        }
        return "Turn \(turn): empty output."
    }

    private func summarizeFunctionCall(_ functionCall: ParsedFunctionCall) -> String {
        guard
            let data = functionCall.arguments.data(using: .utf8),
            let object = try? jsonDecoder.decode([String: OpenAIJSONValue].self, from: data)
        else {
            return "\(functionCall.name)(invalid_arguments)"
        }

        if functionCall.name.lowercased() == "terminal_exec" {
            let executable = firstStringValue(from: object, keys: ["executable"]) ?? ""
            let args: [String]
            if let array = object["args"]?.arrayValue {
                args = array.compactMap(\.stringValue)
            } else {
                args = []
            }
            let argsPreview = args.prefix(6).joined(separator: " ")
            let suffix = args.count > 6 ? " ..." : ""
            return "terminal_exec(executable=\"\(truncate(executable, limit: 80))\", args=\"\(truncate(argsPreview + suffix, limit: 160))\")"
        }

        let action = (object["action"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if action.isEmpty {
            return "\(functionCall.name)(missing_action)"
        }

        switch action.lowercased() {
        case "mouse_move", "move_mouse", "move", "left_click", "double_click", "right_click":
            let point = extractPoint(from: object)
            let xText = point.map { String($0.0) } ?? "?"
            let yText = point.map { String($0.1) } ?? "?"
            return "\(functionCall.name).\(action)(x=\(xText),y=\(yText))"
        case "scroll":
            if let (dx, dy) = extractScrollDelta(from: object) {
                return "\(functionCall.name).scroll(dx=\(dx),dy=\(dy))"
            }
            return "\(functionCall.name).scroll"
        case "type":
            let text = object["text"]?.stringValue ?? ""
            return "\(functionCall.name).type(text=\"\(truncate(text, limit: 80))\")"
        case "key":
            let raw = firstStringValue(from: object, keys: ["key", "text", "keys"]) ?? ""
            return "\(functionCall.name).key(\"\(truncate(raw, limit: 80))\")"
        case "open_app":
            let app = firstStringValue(from: object, keys: ["app", "name"]) ?? ""
            return "\(functionCall.name).open_app(\"\(truncate(app, limit: 80))\")"
        case "open_url":
            let url = firstStringValue(from: object, keys: ["url"]) ?? ""
            return "\(functionCall.name).open_url(\"\(truncate(url, limit: 140))\")"
        case "wait":
            let seconds = object["seconds"]?.doubleValue ?? object["duration"]?.doubleValue
            if let seconds {
                return "\(functionCall.name).wait(\(String(format: "%.1f", seconds))s)"
            }
            return "\(functionCall.name).wait"
        case "cursor_position", "get_cursor_position", "mouse_position":
            return "\(functionCall.name).cursor_position"
        case "screenshot":
            return "\(functionCall.name).screenshot"
        default:
            return "\(functionCall.name).\(action)"
        }
    }

    private func recordTrace(kind: ExecutionTraceKind, _ message: String) {
        traceSink?(ExecutionTraceEntry(kind: kind, message: truncate(message, limit: 900)))
    }

    private func truncate(_ message: String, limit: Int) -> String {
        let cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > limit else {
            return cleaned
        }
        let prefix = cleaned.prefix(limit)
        return "\(prefix)..."
    }

    nonisolated private static func currentCursorPosition() -> (x: Int, y: Int)? {
        if let event = CGEvent(source: nil) {
            let point = event.location
            return (Int(point.x.rounded()), Int(point.y.rounded()))
        }
        let point = NSEvent.mouseLocation
        return (Int(point.x.rounded()), Int(point.y.rounded()))
    }

    nonisolated private static func captureMainDisplayScreenshot() throws -> OpenAICapturedScreenshot {
        try captureMainDisplayScreenshot(excludingWindowNumber: nil)
    }

    nonisolated static func captureMainDisplayScreenshot(excludingWindowNumber: Int?) throws -> OpenAICapturedScreenshot {
        let screenshot = try AnthropicComputerUseRunner.captureMainDisplayScreenshot(excludingWindowNumber: excludingWindowNumber)
        return OpenAICapturedScreenshot(
            width: screenshot.width,
            height: screenshot.height,
            captureWidthPx: screenshot.captureWidthPx,
            captureHeightPx: screenshot.captureHeightPx,
            coordinateSpaceWidthPx: screenshot.coordinateSpaceWidthPx,
            coordinateSpaceHeightPx: screenshot.coordinateSpaceHeightPx,
            mediaType: screenshot.mediaType,
            base64Data: screenshot.base64Data,
            byteCount: screenshot.byteCount
        )
    }
}

struct OpenAIAutomationEngine: AutomationEngine {
    private let runner: any LLMExecutionToolLoopRunner
    private let executor: any DesktopActionExecutor

    init(
        runner: any LLMExecutionToolLoopRunner,
        executor: any DesktopActionExecutor = SystemDesktopActionExecutor()
    ) {
        self.runner = runner
        self.executor = executor
    }

    func run(taskMarkdown: String) async -> AutomationRunResult {
        do {
            return try await runner.runToolLoop(taskMarkdown: taskMarkdown, executor: executor)
        } catch let error as OpenAIExecutionPlannerError {
            return AutomationRunResult(
                outcome: .failed,
                executedSteps: [],
                generatedQuestions: [],
                errorMessage: error.errorDescription,
                llmSummary: nil
            )
        } catch is CancellationError {
            return AutomationRunResult(
                outcome: .cancelled,
                executedSteps: [],
                generatedQuestions: [],
                errorMessage: nil,
                llmSummary: "Cancelled by user."
            )
        } catch {
            return AutomationRunResult(
                outcome: .failed,
                executedSteps: [],
                generatedQuestions: [],
                errorMessage: "Failed during execution tool loop.",
                llmSummary: nil
            )
        }
    }
}

private struct OpenAIResponsesResponse: Decodable {
    var id: String?
    var output: [OpenAIResponseOutputItem]?
    var outputText: String?

    enum CodingKeys: String, CodingKey {
        case id
        case output
        case outputText = "output_text"
    }
}

private struct OpenAIResponseOutputItem: Decodable {
    var type: String
    var id: String?
    var callID: String?
    var name: String?
    var arguments: OpenAIJSONValue?
    var content: [OpenAIResponseMessageContent]?
    var text: String?

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case callID = "call_id"
        case name
        case arguments
        case content
        case text
    }
}

private struct OpenAIResponseMessageContent: Decodable {
    var type: String
    var text: String?
}

private struct OpenAIErrorEnvelope: Decodable {
    struct Payload: Decodable {
        var message: String?
    }

    var error: Payload?
}

private struct OpenAIToolLoopCompletionPayload: Decodable {
    var status: String
    var summary: String?
    var error: String?
    var questions: [String]?
}

private enum OpenAIJSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: OpenAIJSONValue])
    case array([OpenAIJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: OpenAIJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([OpenAIJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return String(value)
        default:
            return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value):
            return value
        case .string(let value):
            return Double(value)
        default:
            return nil
        }
    }

    var intValue: Int? {
        guard let double = doubleValue else {
            return nil
        }
        return Int(double.rounded())
    }

    var objectValue: [String: OpenAIJSONValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }

    var arrayValue: [OpenAIJSONValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }

    func jsonString(using encoder: JSONEncoder) -> String? {
        if case .string(let raw) = self {
            return raw
        }
        guard let data = try? encoder.encode(self),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }
}
