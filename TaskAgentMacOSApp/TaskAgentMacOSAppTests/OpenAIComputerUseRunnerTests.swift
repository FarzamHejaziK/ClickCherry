import Foundation
import Testing
@testable import TaskAgentMacOSApp

private final class OpenAIStubAPIKeyStore: APIKeyStore {
    private let values: [ProviderIdentifier: String]
    private let shouldThrowOnRead: Bool

    init(values: [ProviderIdentifier: String] = [:], shouldThrowOnRead: Bool = false) {
        self.values = values
        self.shouldThrowOnRead = shouldThrowOnRead
    }

    func hasKey(for provider: ProviderIdentifier) -> Bool {
        guard let value = values[provider] else { return false }
        return !value.isEmpty
    }

    func readKey(for provider: ProviderIdentifier) throws -> String? {
        if shouldThrowOnRead {
            throw KeychainStoreError.unhandledStatus(-1)
        }
        return values[provider]
    }

    func setKey(_ key: String?, for provider: ProviderIdentifier) throws {}
}

private final class OpenAIQueueURLProtocol: URLProtocol {
    static let lock = NSLock()
    static var handlers: [((URLRequest) throws -> (HTTPURLResponse, Data))] = []
    static var capturedRequests: [URLRequest] = []

    static func reset() {
        lock.lock()
        handlers = []
        capturedRequests = []
        lock.unlock()
    }

    static func enqueue(_ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock()
        handlers.append(handler)
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        OpenAIQueueURLProtocol.lock.lock()
        OpenAIQueueURLProtocol.capturedRequests.append(request)
        let handler = OpenAIQueueURLProtocol.handlers.isEmpty ? nil : OpenAIQueueURLProtocol.handlers.removeFirst()
        OpenAIQueueURLProtocol.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "OpenAIQueueURLProtocol", code: -1))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private struct OpenAIXY: Equatable {
    var x: Int
    var y: Int
}

private final class OpenAIMockDesktopExecutor: DesktopActionExecutor {
    private(set) var openedApps: [String] = []
    private(set) var openedURLs: [URL] = []
    private(set) var shortcuts: [(key: String, command: Bool, option: Bool, control: Bool, shift: Bool)] = []
    private(set) var typedTexts: [String] = []
    private(set) var clicks: [OpenAIXY] = []
    private(set) var moves: [OpenAIXY] = []
    private(set) var rightClicks: [OpenAIXY] = []
    private(set) var scrolls: [(dx: Int, dy: Int)] = []

    func openApp(named appName: String) throws {
        openedApps.append(appName)
    }

    func openURL(_ url: URL) throws {
        openedURLs.append(url)
    }

    func sendShortcut(key: String, command: Bool, option: Bool, control: Bool, shift: Bool) throws {
        shortcuts.append((key: key, command: command, option: option, control: control, shift: shift))
    }

    func typeText(_ text: String) throws {
        typedTexts.append(text)
    }

    func click(x: Int, y: Int) throws {
        clicks.append(OpenAIXY(x: x, y: y))
    }

    func moveMouse(x: Int, y: Int) throws {
        moves.append(OpenAIXY(x: x, y: y))
    }

    func rightClick(x: Int, y: Int) throws {
        rightClicks.append(OpenAIXY(x: x, y: y))
    }

    func scroll(deltaX: Int, deltaY: Int) throws {
        scrolls.append((dx: deltaX, dy: deltaY))
    }
}

private final class RoutingMockAutomationEngine: AutomationEngine {
    private(set) var runCallCount = 0
    let result: AutomationRunResult

    init(result: AutomationRunResult) {
        self.result = result
    }

    func run(taskMarkdown: String) async -> AutomationRunResult {
        runCallCount += 1
        return result
    }
}

@Suite(.serialized)
@MainActor
struct OpenAIComputerUseRunnerTests {
    @Test
    func runToolLoopFailsWhenOpenAIKeyMissing() async throws {
        let (promptCatalog, tempRoot) = try makePromptCatalog()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let runner = OpenAIComputerUseRunner(
            apiKeyStore: OpenAIStubAPIKeyStore(),
            promptCatalog: promptCatalog,
            session: makeSession()
        )

        do {
            _ = try await runner.runToolLoop(taskMarkdown: "# Task", executor: OpenAIMockDesktopExecutor())
            #expect(Bool(false))
        } catch let error as OpenAIExecutionPlannerError {
            #expect(error == .missingAPIKey)
        }
    }

    @Test
    func runToolLoopExecutesToolUseAndReturnsSuccess() async throws {
        let (promptCatalog, tempRoot) = try makePromptCatalog()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        OpenAIQueueURLProtocol.reset()
        defer { OpenAIQueueURLProtocol.reset() }

        OpenAIQueueURLProtocol.enqueue { request in
            guard
                let bodyData = Self.requestBodyData(from: request),
                let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                let model = json["model"] as? String,
                let tools = json["tools"] as? [[String: Any]],
                let input = json["input"] as? [[String: Any]],
                let firstTurn = input.first,
                let content = firstTurn["content"] as? [[String: Any]]
            else {
                throw NSError(domain: "OpenAIComputerUseRunnerTests", code: 0)
            }

            #expect(model == "gpt-5.2-codex")
            #expect(tools.compactMap { $0["name"] as? String }.contains("desktop_action"))
            #expect(tools.compactMap { $0["name"] as? String }.contains("terminal_exec"))
            #expect(content.contains(where: { ($0["type"] as? String) == "input_image" }))

            let responseBody = """
            {
              "id": "resp_1",
              "output": [
                {
                  "type": "function_call",
                  "id": "fc_1",
                  "call_id": "call_1",
                  "name": "desktop_action",
                  "arguments": "{\\"action\\":\\"type\\",\\"text\\":\\"hello world\\"}"
                }
              ]
            }
            """
            return (Self.response(url: request.url!, code: 200), Data(responseBody.utf8))
        }

        OpenAIQueueURLProtocol.enqueue { request in
            guard
                let bodyData = Self.requestBodyData(from: request),
                let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                let previousResponseId = json["previous_response_id"] as? String,
                let input = json["input"] as? [[String: Any]],
                let functionOutput = input.first(where: { ($0["type"] as? String) == "function_call_output" }),
                let functionCallId = functionOutput["call_id"] as? String,
                let output = functionOutput["output"] as? String
            else {
                throw NSError(domain: "OpenAIComputerUseRunnerTests", code: 1)
            }

            #expect(previousResponseId == "resp_1")
            #expect(functionCallId == "call_1")
            #expect(output.contains("\"ok\":true"))

            let responseBody = """
            {
              "id": "resp_2",
              "output": [
                {
                  "type": "message",
                  "content": [
                    {
                      "type": "output_text",
                      "text": "{\\"status\\":\\"SUCCESS\\",\\"summary\\":\\"Task completed\\",\\"error\\":null,\\"questions\\":[]}"
                    }
                  ]
                }
              ]
            }
            """
            return (Self.response(url: request.url!, code: 200), Data(responseBody.utf8))
        }

        let runner = OpenAIComputerUseRunner(
            apiKeyStore: OpenAIStubAPIKeyStore(values: [.openAI: "openai-test-key"]),
            promptCatalog: promptCatalog,
            session: makeSession(),
            screenshotProvider: {
                let data = Data("png".utf8)
                return OpenAICapturedScreenshot(
                    width: 1280,
                    height: 800,
                    captureWidthPx: 1280,
                    captureHeightPx: 800,
                    coordinateSpaceWidthPx: 1280,
                    coordinateSpaceHeightPx: 800,
                    mediaType: "image/png",
                    base64Data: data.base64EncodedString(),
                    byteCount: data.count
                )
            }
        )
        let executor = OpenAIMockDesktopExecutor()

        let result = try await runner.runToolLoop(taskMarkdown: "# Task\nType hello world", executor: executor)

        #expect(result.outcome == .success)
        #expect(result.generatedQuestions.isEmpty)
        #expect(result.executedSteps.contains("Type text 'hello world'"))
        #expect(result.llmSummary == "Task completed")
        #expect(executor.typedTexts == ["hello world"])
    }

    @Test
    func runToolLoopScalesCoordinatesWhenScreenshotDownscaled() async throws {
        let (promptCatalog, tempRoot) = try makePromptCatalog()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        OpenAIQueueURLProtocol.reset()
        defer { OpenAIQueueURLProtocol.reset() }

        OpenAIQueueURLProtocol.enqueue { request in
            let responseBody = """
            {
              "id": "resp_1",
              "output": [
                {
                  "type": "function_call",
                  "id": "fc_1",
                  "call_id": "call_1",
                  "name": "desktop_action",
                  "arguments": "{\\"action\\":\\"left_click\\",\\"x\\":100,\\"y\\":200}"
                }
              ]
            }
            """
            return (Self.response(url: request.url!, code: 200), Data(responseBody.utf8))
        }

        OpenAIQueueURLProtocol.enqueue { request in
            let responseBody = """
            {
              "id": "resp_2",
              "output": [
                {
                  "type": "message",
                  "content": [
                    {
                      "type": "output_text",
                      "text": "{\\"status\\":\\"SUCCESS\\",\\"summary\\":\\"ok\\",\\"error\\":null,\\"questions\\":[]}"
                    }
                  ]
                }
              ]
            }
            """
            return (Self.response(url: request.url!, code: 200), Data(responseBody.utf8))
        }

        let runner = OpenAIComputerUseRunner(
            apiKeyStore: OpenAIStubAPIKeyStore(values: [.openAI: "openai-test-key"]),
            promptCatalog: promptCatalog,
            session: makeSession(),
            screenshotProvider: {
                let data = Data("jpg".utf8)
                return OpenAICapturedScreenshot(
                    width: 1280,
                    height: 720,
                    captureWidthPx: 2560,
                    captureHeightPx: 1440,
                    coordinateSpaceWidthPx: 2560,
                    coordinateSpaceHeightPx: 1440,
                    mediaType: "image/jpeg",
                    base64Data: data.base64EncodedString(),
                    byteCount: data.count
                )
            }
        )
        let executor = OpenAIMockDesktopExecutor()

        _ = try await runner.runToolLoop(taskMarkdown: "# Task\nClick target", executor: executor)
        #expect(executor.clicks == [OpenAIXY(x: 200, y: 400)])
    }

    @Test
    func runToolLoopExecutesTerminalExecToolUseAndReturnsOutput() async throws {
        let (promptCatalog, tempRoot) = try makePromptCatalog()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        OpenAIQueueURLProtocol.reset()
        defer { OpenAIQueueURLProtocol.reset() }

        OpenAIQueueURLProtocol.enqueue { request in
            let responseBody = """
            {
              "id": "resp_1",
              "output": [
                {
                  "type": "function_call",
                  "id": "fc_1",
                  "call_id": "call_1",
                  "name": "terminal_exec",
                  "arguments": "{\\"executable\\":\\"echo\\",\\"args\\":[\\"hello\\"]}"
                }
              ]
            }
            """
            return (Self.response(url: request.url!, code: 200), Data(responseBody.utf8))
        }

        OpenAIQueueURLProtocol.enqueue { request in
            guard
                let bodyData = Self.requestBodyData(from: request),
                let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                let input = json["input"] as? [[String: Any]],
                let functionOutput = input.first(where: { ($0["type"] as? String) == "function_call_output" }),
                let callID = functionOutput["call_id"] as? String,
                let output = functionOutput["output"] as? String
            else {
                throw NSError(domain: "OpenAIComputerUseRunnerTests", code: 12)
            }

            #expect(callID == "call_1")
            #expect(output.contains("\"exit_code\":0"))
            #expect(output.contains("hello"))

            let responseBody = """
            {
              "id": "resp_2",
              "output": [
                {
                  "type": "message",
                  "content": [
                    {
                      "type": "output_text",
                      "text": "{\\"status\\":\\"SUCCESS\\",\\"summary\\":\\"ok\\",\\"error\\":null,\\"questions\\":[]}"
                    }
                  ]
                }
              ]
            }
            """
            return (Self.response(url: request.url!, code: 200), Data(responseBody.utf8))
        }

        let runner = OpenAIComputerUseRunner(
            apiKeyStore: OpenAIStubAPIKeyStore(values: [.openAI: "openai-test-key"]),
            promptCatalog: promptCatalog,
            session: makeSession(),
            screenshotProvider: {
                let data = Data("png".utf8)
                return OpenAICapturedScreenshot(
                    width: 1280,
                    height: 800,
                    captureWidthPx: 1280,
                    captureHeightPx: 800,
                    coordinateSpaceWidthPx: 1280,
                    coordinateSpaceHeightPx: 800,
                    mediaType: "image/png",
                    base64Data: data.base64EncodedString(),
                    byteCount: data.count
                )
            }
        )

        let result = try await runner.runToolLoop(taskMarkdown: "# Task", executor: OpenAIMockDesktopExecutor())
        #expect(result.outcome == .success)
        #expect(result.executedSteps.contains(where: { $0.contains("Terminal exec:") }))
    }

    @Test
    func runToolLoopRejectsVisualTerminalCommandAndRequestsDesktopActionTool() async throws {
        let (promptCatalog, tempRoot) = try makePromptCatalog()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        OpenAIQueueURLProtocol.reset()
        defer { OpenAIQueueURLProtocol.reset() }

        OpenAIQueueURLProtocol.enqueue { request in
            let responseBody = """
            {
              "id": "resp_1",
              "output": [
                {
                  "type": "function_call",
                  "id": "fc_1",
                  "call_id": "call_1",
                  "name": "terminal_exec",
                  "arguments": "{\\"executable\\":\\"osascript\\",\\"args\\":[\\"-e\\",\\"tell application \\\\\\"System Events\\\\\\" to tell process \\\\\\"Dock\\\\\\" to get every UI element\\"]}"
                }
              ]
            }
            """
            return (Self.response(url: request.url!, code: 200), Data(responseBody.utf8))
        }

        OpenAIQueueURLProtocol.enqueue { request in
            guard
                let bodyData = Self.requestBodyData(from: request),
                let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                let input = json["input"] as? [[String: Any]],
                let functionOutput = input.first(where: { ($0["type"] as? String) == "function_call_output" }),
                let output = functionOutput["output"] as? String
            else {
                throw NSError(domain: "OpenAIComputerUseRunnerTests", code: 13)
            }

            #expect(output.contains("\"ok\":false"))
            #expect(output.contains("Use tool 'desktop_action'"))

            let responseBody = """
            {
              "id": "resp_2",
              "output": [
                {
                  "type": "message",
                  "content": [
                    {
                      "type": "output_text",
                      "text": "{\\"status\\":\\"SUCCESS\\",\\"summary\\":\\"ok\\",\\"error\\":null,\\"questions\\":[]}"
                    }
                  ]
                }
              ]
            }
            """
            return (Self.response(url: request.url!, code: 200), Data(responseBody.utf8))
        }

        let runner = OpenAIComputerUseRunner(
            apiKeyStore: OpenAIStubAPIKeyStore(values: [.openAI: "openai-test-key"]),
            promptCatalog: promptCatalog,
            session: makeSession(),
            screenshotProvider: {
                let data = Data("png".utf8)
                return OpenAICapturedScreenshot(
                    width: 1280,
                    height: 800,
                    captureWidthPx: 1280,
                    captureHeightPx: 800,
                    coordinateSpaceWidthPx: 1280,
                    coordinateSpaceHeightPx: 800,
                    mediaType: "image/png",
                    base64Data: data.base64EncodedString(),
                    byteCount: data.count
                )
            }
        )

        let result = try await runner.runToolLoop(taskMarkdown: "# Task", executor: OpenAIMockDesktopExecutor())
        #expect(result.outcome == .success)
        #expect(result.executedSteps.contains(where: { $0.contains("Terminal exec:") }) == false)
    }

    @Test
    func runToolLoopExecutesTerminalExecUsingPathResolvedExecutable() async throws {
        let (promptCatalog, tempRoot) = try makePromptCatalog()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        OpenAIQueueURLProtocol.reset()
        defer { OpenAIQueueURLProtocol.reset() }

        OpenAIQueueURLProtocol.enqueue { request in
            let responseBody = """
            {
              "id": "resp_1",
              "output": [
                {
                  "type": "function_call",
                  "id": "fc_1",
                  "call_id": "call_1",
                  "name": "terminal_exec",
                  "arguments": "{\\"executable\\":\\"true\\"}"
                }
              ]
            }
            """
            return (Self.response(url: request.url!, code: 200), Data(responseBody.utf8))
        }

        OpenAIQueueURLProtocol.enqueue { request in
            guard
                let bodyData = Self.requestBodyData(from: request),
                let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                let input = json["input"] as? [[String: Any]],
                let functionOutput = input.first(where: { ($0["type"] as? String) == "function_call_output" }),
                let output = functionOutput["output"] as? String
            else {
                throw NSError(domain: "OpenAIComputerUseRunnerTests", code: 14)
            }

            #expect(output.contains("\"exit_code\":0"))
            #expect(output.contains("\"ok\":true"))

            let responseBody = """
            {
              "id": "resp_2",
              "output": [
                {
                  "type": "message",
                  "content": [
                    {
                      "type": "output_text",
                      "text": "{\\"status\\":\\"SUCCESS\\",\\"summary\\":\\"ok\\",\\"error\\":null,\\"questions\\":[]}"
                    }
                  ]
                }
              ]
            }
            """
            return (Self.response(url: request.url!, code: 200), Data(responseBody.utf8))
        }

        let runner = OpenAIComputerUseRunner(
            apiKeyStore: OpenAIStubAPIKeyStore(values: [.openAI: "openai-test-key"]),
            promptCatalog: promptCatalog,
            session: makeSession(),
            screenshotProvider: {
                let data = Data("png".utf8)
                return OpenAICapturedScreenshot(
                    width: 1280,
                    height: 800,
                    captureWidthPx: 1280,
                    captureHeightPx: 800,
                    coordinateSpaceWidthPx: 1280,
                    coordinateSpaceHeightPx: 800,
                    mediaType: "image/png",
                    base64Data: data.base64EncodedString(),
                    byteCount: data.count
                )
            }
        )

        let result = try await runner.runToolLoop(taskMarkdown: "# Task", executor: OpenAIMockDesktopExecutor())
        #expect(result.outcome == .success)
        #expect(result.executedSteps.contains(where: { $0.contains("Terminal exec: true") }))
    }

    @Test
    func providerRoutingUsesSelectedOpenAIWhenConfigured() async {
        let keyStore = OpenAIStubAPIKeyStore(values: [.openAI: "openai-key", .anthropic: "anthropic-key"])
        let openAI = RoutingMockAutomationEngine(
            result: AutomationRunResult(
                outcome: .success,
                executedSteps: ["openai-step"],
                generatedQuestions: [],
                errorMessage: nil,
                llmSummary: nil
            )
        )
        let anthropic = RoutingMockAutomationEngine(
            result: AutomationRunResult(
                outcome: .success,
                executedSteps: ["anthropic-step"],
                generatedQuestions: [],
                errorMessage: nil,
                llmSummary: nil
            )
        )

        let router = ProviderRoutingAutomationEngine(
            apiKeyStore: keyStore,
            openAIEngine: openAI,
            anthropicEngine: anthropic,
            preferredProvider: { .openAI }
        )

        let result = await router.run(taskMarkdown: "# Task")
        #expect(result.executedSteps == ["openai-step"])
        #expect(openAI.runCallCount == 1)
        #expect(anthropic.runCallCount == 0)
    }

    @Test
    func providerRoutingUsesSelectedAnthropicWhenConfigured() async {
        let keyStore = OpenAIStubAPIKeyStore(values: [.openAI: "openai-key", .anthropic: "anthropic-key"])
        let openAI = RoutingMockAutomationEngine(
            result: AutomationRunResult(
                outcome: .success,
                executedSteps: ["openai-step"],
                generatedQuestions: [],
                errorMessage: nil,
                llmSummary: nil
            )
        )
        let anthropic = RoutingMockAutomationEngine(
            result: AutomationRunResult(
                outcome: .success,
                executedSteps: ["anthropic-step"],
                generatedQuestions: [],
                errorMessage: nil,
                llmSummary: nil
            )
        )

        let router = ProviderRoutingAutomationEngine(
            apiKeyStore: keyStore,
            openAIEngine: openAI,
            anthropicEngine: anthropic,
            preferredProvider: { .anthropic }
        )

        let result = await router.run(taskMarkdown: "# Task")
        #expect(result.executedSteps == ["anthropic-step"])
        #expect(openAI.runCallCount == 0)
        #expect(anthropic.runCallCount == 1)
    }

    @Test
    func providerRoutingFailsWhenSelectedProviderKeyMissing() async {
        let keyStore = OpenAIStubAPIKeyStore(values: [.anthropic: "anthropic-key"])
        let openAI = RoutingMockAutomationEngine(
            result: AutomationRunResult(
                outcome: .success,
                executedSteps: ["openai-step"],
                generatedQuestions: [],
                errorMessage: nil,
                llmSummary: nil
            )
        )
        let anthropic = RoutingMockAutomationEngine(
            result: AutomationRunResult(
                outcome: .success,
                executedSteps: ["anthropic-step"],
                generatedQuestions: [],
                errorMessage: nil,
                llmSummary: nil
            )
        )

        let router = ProviderRoutingAutomationEngine(
            apiKeyStore: keyStore,
            openAIEngine: openAI,
            anthropicEngine: anthropic,
            preferredProvider: { .openAI }
        )

        let result = await router.run(taskMarkdown: "# Task")
        #expect(result.outcome == .failed)
        #expect(result.errorMessage?.contains("Selected execution provider is OpenAI") == true)
        #expect(openAI.runCallCount == 0)
        #expect(anthropic.runCallCount == 0)
    }

    private static func response(url: URL, code: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
    }

    private static func requestBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }

        let bufferSize = 16 * 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var data = Data()
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OpenAIQueueURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makePromptCatalog() throws -> (PromptCatalogService, URL) {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let promptDir = tempRoot.appendingPathComponent("execution_agent_openai", isDirectory: true)
        try fm.createDirectory(at: promptDir, withIntermediateDirectories: true)
        try """
        PROMPT_HEADER
        OS: {{OS_VERSION}}
        SCREEN_WIDTH: {{SCREEN_WIDTH}}
        SCREEN_HEIGHT: {{SCREEN_HEIGHT}}
        TASK_MARKDOWN:
        {{TASK_MARKDOWN}}
        PROMPT_FOOTER
        """.write(to: promptDir.appendingPathComponent("prompt.md"), atomically: true, encoding: .utf8)
        try """
        version: v1
        llm: gpt-5.2-codex
        """.write(to: promptDir.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)

        return (PromptCatalogService(promptsRootURL: tempRoot, fileManager: fm), tempRoot)
    }
}
