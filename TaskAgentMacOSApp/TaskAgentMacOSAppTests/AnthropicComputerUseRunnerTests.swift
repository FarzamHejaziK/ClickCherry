import Foundation
import Testing
@testable import TaskAgentMacOSApp

private final class AnthropicStubAPIKeyStore: APIKeyStore {
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

private final class AnthropicQueueURLProtocol: URLProtocol {
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
        AnthropicQueueURLProtocol.lock.lock()
        AnthropicQueueURLProtocol.capturedRequests.append(request)
        let handler = AnthropicQueueURLProtocol.handlers.isEmpty ? nil : AnthropicQueueURLProtocol.handlers.removeFirst()
        AnthropicQueueURLProtocol.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "AnthropicQueueURLProtocol", code: -1))
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

private struct XY: Equatable {
    var x: Int
    var y: Int
}

private struct DXDY: Equatable {
    var dx: Int
    var dy: Int
}

private final class AnthropicMockDesktopExecutor: DesktopActionExecutor {
    private(set) var openedApps: [String] = []
    private(set) var openedURLs: [URL] = []
    private(set) var shortcuts: [(key: String, command: Bool, option: Bool, control: Bool, shift: Bool)] = []
    private(set) var typedTexts: [String] = []
    private(set) var clicks: [XY] = []
    private(set) var moves: [XY] = []
    private(set) var rightClicks: [XY] = []
    private(set) var scrolls: [DXDY] = []

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
        clicks.append(XY(x: x, y: y))
    }

    func moveMouse(x: Int, y: Int) throws {
        moves.append(XY(x: x, y: y))
    }

    func rightClick(x: Int, y: Int) throws {
        rightClicks.append(XY(x: x, y: y))
    }

    func scroll(deltaX: Int, deltaY: Int) throws {
        scrolls.append(DXDY(dx: deltaX, dy: deltaY))
    }
}

@Suite(.serialized)
@MainActor
struct AnthropicComputerUseRunnerTests {
    @Test
    func runToolLoopFailsWhenAnthropicKeyMissing() async throws {
        let (promptCatalog, tempRoot) = try makePromptCatalog()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let runner = AnthropicComputerUseRunner(
            apiKeyStore: AnthropicStubAPIKeyStore(),
            promptCatalog: promptCatalog,
            session: makeSession()
        )

        do {
            _ = try await runner.runToolLoop(taskMarkdown: "# Task", executor: AnthropicMockDesktopExecutor())
            #expect(Bool(false))
        } catch let error as AnthropicExecutionPlannerError {
            #expect(error == .missingAPIKey)
        }
    }

    @Test
    func runToolLoopExecutesToolUseAndReturnsSuccess() async throws {
        let (promptCatalog, tempRoot) = try makePromptCatalog()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        AnthropicQueueURLProtocol.reset()
        defer { AnthropicQueueURLProtocol.reset() }

        AnthropicQueueURLProtocol.enqueue { request in
            #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "computer-use-2025-11-24")
            guard
                let bodyData = Self.requestBodyData(from: request),
                let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                let tools = json["tools"] as? [[String: Any]],
                let firstTool = tools.first,
                let messages = json["messages"] as? [[String: Any]],
                let firstMessage = messages.first,
                let content = firstMessage["content"] as? [[String: Any]],
                let firstText = content.first?["text"] as? String
            else {
                throw NSError(domain: "AnthropicComputerUseRunnerTests", code: 0)
            }
            #expect(firstTool["type"] as? String == "computer_20251124")
            #expect(firstText.contains("PROMPT_HEADER"))
            #expect(firstText.contains("TASK_MARKDOWN:\n# Task\nType hello world"))

            let responseBody = """
            {
              "content": [
                {
                  "type": "tool_use",
                  "id": "toolu_1",
                  "name": "computer",
                  "input": { "action": "type", "text": "hello world" }
                }
              ]
            }
            """
            return (Self.response(url: request.url!, code: 200), Data(responseBody.utf8))
        }

        AnthropicQueueURLProtocol.enqueue { request in
            let body = """
            {
              "content": [
                {
                  "type": "text",
                  "text": "{\\"status\\":\\"SUCCESS\\",\\"summary\\":\\"Task completed\\",\\"error\\":null,\\"questions\\":[]}"
                }
              ]
            }
            """
            return (Self.response(url: request.url!, code: 200), Data(body.utf8))
        }

        let runner = AnthropicComputerUseRunner(
            apiKeyStore: AnthropicStubAPIKeyStore(values: [.anthropic: "anthropic-test-key"]),
            promptCatalog: promptCatalog,
            session: makeSession(),
            screenshotProvider: {
                let data = Data("png".utf8)
                return AnthropicCapturedScreenshot(
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
        let executor = AnthropicMockDesktopExecutor()

        let result = try await runner.runToolLoop(taskMarkdown: "# Task\nType hello world", executor: executor)

        #expect(result.outcome == .success)
        #expect(result.generatedQuestions.isEmpty)
        #expect(result.executedSteps.contains("Type text 'hello world'"))
        #expect(result.llmSummary == "Task completed")
        #expect(executor.typedTexts == ["hello world"])
    }

    @Test
    func runToolLoopExecutesAllSupportedActions() async throws {
        let (promptCatalog, tempRoot) = try makePromptCatalog()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        AnthropicQueueURLProtocol.reset()
        defer { AnthropicQueueURLProtocol.reset() }

        AnthropicQueueURLProtocol.enqueue { request in
            let body = """
            {
              "content": [
                { "type": "tool_use", "id": "toolu_1", "name": "computer", "input": { "action": "screenshot" } },
                { "type": "tool_use", "id": "toolu_2", "name": "computer", "input": { "action": "scroll", "delta_x": 0, "delta_y": -600 } },
                { "type": "tool_use", "id": "toolu_3", "name": "computer", "input": { "action": "mouse_move", "coordinate": [10, 20] } },
                { "type": "tool_use", "id": "toolu_4", "name": "computer", "input": { "action": "left_click", "coordinate": [30, 40] } },
                { "type": "tool_use", "id": "toolu_5", "name": "computer", "input": { "action": "right_click", "x": 50, "y": 60 } },
                { "type": "tool_use", "id": "toolu_6", "name": "computer", "input": { "action": "double_click", "x": 70, "y": 80 } },
                { "type": "tool_use", "id": "toolu_7", "name": "computer", "input": { "action": "type", "text": "hello" } },
                { "type": "tool_use", "id": "toolu_8", "name": "computer", "input": { "action": "key", "text": "cmd+space" } },
                { "type": "tool_use", "id": "toolu_9", "name": "computer", "input": { "action": "open_app", "app": "Safari" } },
                { "type": "tool_use", "id": "toolu_10", "name": "computer", "input": { "action": "open_url", "url": "https://example.com" } },
                { "type": "tool_use", "id": "toolu_11", "name": "computer", "input": { "action": "wait", "seconds": 0 } }
              ]
            }
            """
            return (Self.response(url: request.url!, code: 200), Data(body.utf8))
        }

        AnthropicQueueURLProtocol.enqueue { request in
            let body = """
            {
              "content": [
                {
                  "type": "text",
                  "text": "{\\"status\\":\\"SUCCESS\\",\\"summary\\":\\"Task completed\\",\\"error\\":null,\\"questions\\":[]}"
                }
              ]
            }
            """
            return (Self.response(url: request.url!, code: 200), Data(body.utf8))
        }

        let runner = AnthropicComputerUseRunner(
            apiKeyStore: AnthropicStubAPIKeyStore(values: [.anthropic: "anthropic-test-key"]),
            promptCatalog: promptCatalog,
            session: makeSession(),
            screenshotProvider: {
                let data = Data("png".utf8)
                return AnthropicCapturedScreenshot(
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
        let executor = AnthropicMockDesktopExecutor()

        let result = try await runner.runToolLoop(taskMarkdown: "# Task", executor: executor)

        #expect(result.outcome == .success)
        #expect(executor.scrolls == [DXDY(dx: 0, dy: -600)])
        #expect(executor.moves == [XY(x: 10, y: 20)])
        #expect(executor.clicks == [XY(x: 30, y: 40), XY(x: 70, y: 80), XY(x: 70, y: 80)])
        #expect(executor.rightClicks == [XY(x: 50, y: 60)])
        #expect(executor.typedTexts == ["hello"])
        #expect(executor.shortcuts.count == 1)
        #expect(executor.shortcuts.first?.command == true)
        #expect(executor.shortcuts.first?.key == " ")
        #expect(executor.openedApps == ["Safari"])
        #expect(executor.openedURLs.map(\.absoluteString) == ["https://example.com"])

        #expect(result.executedSteps.contains("Capture screenshot"))
        #expect(result.executedSteps.contains("Scroll (0, -600)"))
        #expect(result.executedSteps.contains("Move mouse to (10, 20)"))
        #expect(result.executedSteps.contains("Click at (30, 40)"))
        #expect(result.executedSteps.contains("Right click at (50, 60)"))
        #expect(result.executedSteps.contains("Double click at (70, 80)"))
        #expect(result.executedSteps.contains("Type text 'hello'"))
        #expect(result.executedSteps.contains("Press shortcut 'cmd+space'"))
        #expect(result.executedSteps.contains("Open app 'Safari'"))
        #expect(result.executedSteps.contains("Open URL 'https://example.com'"))
        #expect(result.executedSteps.contains("Wait 0.1s"))
    }

    @Test
    func runToolLoopScalesCoordinatesWhenScreenshotDownscaled() async throws {
        let (promptCatalog, tempRoot) = try makePromptCatalog()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        AnthropicQueueURLProtocol.reset()
        defer { AnthropicQueueURLProtocol.reset() }

        AnthropicQueueURLProtocol.enqueue { request in
            let body = """
            {
              "content": [
                { "type": "tool_use", "id": "toolu_1", "name": "computer", "input": { "action": "left_click", "x": 100, "y": 200 } }
              ]
            }
            """
            return (Self.response(url: request.url!, code: 200), Data(body.utf8))
        }

        AnthropicQueueURLProtocol.enqueue { request in
            let body = """
            {
              "content": [
                { "type": "text", "text": "{\\"status\\":\\"SUCCESS\\",\\"summary\\":\\"ok\\",\\"error\\":null,\\"questions\\":[]}" }
              ]
            }
            """
            return (Self.response(url: request.url!, code: 200), Data(body.utf8))
        }

        let runner = AnthropicComputerUseRunner(
            apiKeyStore: AnthropicStubAPIKeyStore(values: [.anthropic: "anthropic-test-key"]),
            promptCatalog: promptCatalog,
            session: makeSession(),
            screenshotProvider: {
                // Simulate sending a downscaled screenshot (tool coordinate space) from a larger physical display.
                let data = Data("jpg".utf8)
                return AnthropicCapturedScreenshot(
                    width: 2560,
                    height: 1440,
                    captureWidthPx: 5120,
                    captureHeightPx: 2880,
                    coordinateSpaceWidthPx: 2560,
                    coordinateSpaceHeightPx: 1440,
                    mediaType: "image/jpeg",
                    base64Data: data.base64EncodedString(),
                    byteCount: data.count
                )
            }
        )
        let executor = AnthropicMockDesktopExecutor()

        _ = try await runner.runToolLoop(taskMarkdown: "# Task\nClick something", executor: executor)

        // Expect mapping into the CGEvent coordinate space (logical pixels/points), not physical capture pixels.
        #expect(executor.clicks == [XY(x: 100, y: 200)])
    }

    @Test
    func runToolLoopReturnsClarificationWhenCompletionNotJSON() async throws {
        let (promptCatalog, tempRoot) = try makePromptCatalog()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        AnthropicQueueURLProtocol.reset()
        defer { AnthropicQueueURLProtocol.reset() }

        AnthropicQueueURLProtocol.enqueue { request in
            let body = """
            {
              "content": [
                { "type": "text", "text": "I need your help deciding the next step." }
              ]
            }
            """
            return (Self.response(url: request.url!, code: 200), Data(body.utf8))
        }

        let runner = AnthropicComputerUseRunner(
            apiKeyStore: AnthropicStubAPIKeyStore(values: [.anthropic: "anthropic-test-key"]),
            promptCatalog: promptCatalog,
            session: makeSession(),
            screenshotProvider: {
                let data = Data("png".utf8)
                return AnthropicCapturedScreenshot(
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

        let result = try await runner.runToolLoop(taskMarkdown: "# Task", executor: AnthropicMockDesktopExecutor())

        #expect(result.outcome == .needsClarification)
        #expect(result.generatedQuestions.count == 1)
        #expect(result.errorMessage == "Final model response was not valid completion JSON.")
        #expect(result.llmSummary == "I need your help deciding the next step.")
    }

    @Test
    func runToolLoopIncludesNetworkErrorDiagnosticsInRequestFailedMessage() async throws {
        let (promptCatalog, tempRoot) = try makePromptCatalog()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        AnthropicQueueURLProtocol.reset()
        defer { AnthropicQueueURLProtocol.reset() }

        // Exhaust retry budget so we still surface requestFailed diagnostics.
        AnthropicQueueURLProtocol.enqueue { _ in throw URLError(.secureConnectionFailed) }
        AnthropicQueueURLProtocol.enqueue { _ in throw URLError(.secureConnectionFailed) }
        AnthropicQueueURLProtocol.enqueue { _ in throw URLError(.secureConnectionFailed) }

        let runner = AnthropicComputerUseRunner(
            apiKeyStore: AnthropicStubAPIKeyStore(values: [.anthropic: "anthropic-test-key"]),
            promptCatalog: promptCatalog,
            session: makeSession(),
            transportRetryPolicy: .init(maxAttempts: 3, baseDelaySeconds: 0, maxDelaySeconds: 0),
            sleepNanoseconds: { _ in },
            screenshotProvider: {
                let data = Data("png".utf8)
                return AnthropicCapturedScreenshot(
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

        do {
            _ = try await runner.runToolLoop(taskMarkdown: "# Task", executor: AnthropicMockDesktopExecutor())
            #expect(Bool(false))
        } catch let error as AnthropicExecutionPlannerError {
            guard case let .requestFailed(message) = error else {
                #expect(Bool(false))
                return
            }
            #expect(message.contains("domain=NSURLErrorDomain"))
            #expect(message.contains("code=-1200"))
        }
    }

    @Test
    func runToolLoopRetriesOnceOnSecureConnectionFailedThenSucceeds() async throws {
        let (promptCatalog, tempRoot) = try makePromptCatalog()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        AnthropicQueueURLProtocol.reset()
        defer { AnthropicQueueURLProtocol.reset() }

        AnthropicQueueURLProtocol.enqueue { _ in
            throw URLError(.secureConnectionFailed)
        }

        AnthropicQueueURLProtocol.enqueue { request in
            let body = """
            {
              "content": [
                {
                  "type": "tool_use",
                  "id": "toolu_1",
                  "name": "computer",
                  "input": { "action": "type", "text": "hello world" }
                }
              ]
            }
            """
            return (Self.response(url: request.url!, code: 200), Data(body.utf8))
        }

        AnthropicQueueURLProtocol.enqueue { request in
            let body = """
            {
              "content": [
                {
                  "type": "text",
                  "text": "{\\"status\\":\\"SUCCESS\\",\\"summary\\":\\"Task completed\\",\\"error\\":null,\\"questions\\":[]}"
                }
              ]
            }
            """
            return (Self.response(url: request.url!, code: 200), Data(body.utf8))
        }

        let runner = AnthropicComputerUseRunner(
            apiKeyStore: AnthropicStubAPIKeyStore(values: [.anthropic: "anthropic-test-key"]),
            promptCatalog: promptCatalog,
            session: makeSession(),
            transportRetryPolicy: .init(maxAttempts: 3, baseDelaySeconds: 0, maxDelaySeconds: 0),
            sleepNanoseconds: { _ in },
            screenshotProvider: {
                let data = Data("png".utf8)
                return AnthropicCapturedScreenshot(
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

        let executor = AnthropicMockDesktopExecutor()
        let result = try await runner.runToolLoop(taskMarkdown: "# Task\nType hello world", executor: executor)

        #expect(result.outcome == .success)
        #expect(executor.typedTexts == ["hello world"])
        #expect(AnthropicQueueURLProtocol.capturedRequests.count == 3)
    }

    @Test
    func runToolLoopFailsWhenPromptCannotLoad() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let runner = AnthropicComputerUseRunner(
            apiKeyStore: AnthropicStubAPIKeyStore(values: [.anthropic: "anthropic-test-key"]),
            promptCatalog: PromptCatalogService(promptsRootURL: tempRoot, fileManager: fm),
            session: makeSession(),
            screenshotProvider: {
                let data = Data("png".utf8)
                return AnthropicCapturedScreenshot(
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

        do {
            _ = try await runner.runToolLoop(taskMarkdown: "# Task", executor: AnthropicMockDesktopExecutor())
            #expect(Bool(false))
        } catch let error as AnthropicExecutionPlannerError {
            #expect(error == .failedToLoadPrompt("execution_agent"))
        }
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
        config.protocolClasses = [AnthropicQueueURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makePromptCatalog() throws -> (PromptCatalogService, URL) {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let promptDir = tempRoot.appendingPathComponent("execution_agent", isDirectory: true)
        try fm.createDirectory(at: promptDir, withIntermediateDirectories: true)
        try """
        PROMPT_HEADER
        TASK_MARKDOWN:
        {{TASK_MARKDOWN}}

        PROMPT_FOOTER
        """.write(to: promptDir.appendingPathComponent("prompt.md"), atomically: true, encoding: .utf8)
        try """
        version: v1
        llm: claude-opus-4-6
        """.write(to: promptDir.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)

        return (PromptCatalogService(promptsRootURL: tempRoot, fileManager: fm), tempRoot)
    }
}
