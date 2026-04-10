import AppKit
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

private final class OpenAITestWebSocket: OpenAIResponsesWebSocket {
    var sendError: Error?
    var incomingMessages: [Result<String, Error>]
    private(set) var sentTexts: [String] = []
    private(set) var closeReasons: [String] = []

    init(
        incomingMessages: [Result<String, Error>] = [],
        sendError: Error? = nil
    ) {
        self.incomingMessages = incomingMessages
        self.sendError = sendError
    }

    func send(text: String) async throws {
        if let sendError {
            self.sendError = nil
            throw sendError
        }
        sentTexts.append(text)
    }

    func receive() async throws -> String {
        guard !incomingMessages.isEmpty else {
            throw URLError(.badServerResponse)
        }
        let next = incomingMessages.removeFirst()
        switch next {
        case .success(let text):
            return text
        case .failure(let error):
            throw error
        }
    }

    func close(code: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let text = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "\(code.rawValue)"
        closeReasons.append(text)
    }
}

private final class OpenAITestWebSocketConnector: OpenAIResponsesWebSocketConnecting {
    var connectResults: [Result<OpenAITestWebSocket, Error>]
    private(set) var connectCount = 0
    private(set) var capturedURLs: [URL] = []
    private(set) var capturedAPIKeys: [String] = []

    init(connectResults: [Result<OpenAITestWebSocket, Error>]) {
        self.connectResults = connectResults
    }

    func connect(url: URL, apiKey: String) async throws -> any OpenAIResponsesWebSocket {
        connectCount += 1
        capturedURLs.append(url)
        capturedAPIKeys.append(apiKey)
        guard !connectResults.isEmpty else {
            throw URLError(.cannotConnectToHost)
        }
        let next = connectResults.removeFirst()
        switch next {
        case .success(let socket):
            return socket
        case .failure(let error):
            throw error
        }
    }
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

private final class OpenAIMockBrowserExecutor: BrowserActionExecutor {
    private(set) var attachRequests: [BrowserLaunchOptions?] = []
    private(set) var listTabsCalls = 0
    private(set) var selectedTabs: [BrowserTabSelection] = []
    private(set) var navigatedURLs: [URL] = []
    private(set) var clickedQueries: [BrowserElementQuery] = []
    private(set) var typedValues: [(text: String, query: BrowserElementQuery, pressEnter: Bool)] = []
    private(set) var pressedKeys: [String] = []
    private(set) var waitConditions: [BrowserWaitCondition] = []
    private(set) var snapshotCalls = 0
    private(set) var urlReads = 0
    private(set) var titleReads = 0

    var currentPage = BrowserPageState(title: "Example", url: "https://example.com", targetID: "tab-1")
    var tabs: [BrowserTabInfo] = [
        BrowserTabInfo(index: 0, title: "Example", url: "https://example.com", isSelected: true, targetID: "tab-1")
    ]
    var profiles: [BrowserProfileInfo] = [
        BrowserProfileInfo(
            kind: "user_profile",
            displayName: "Farzam Hejazi",
            profileDirectory: "Profile 2",
            userDataDir: "/Users/test/Library/Application Support/Google/Chrome",
            isDefault: false
        )
    ]

    func attachOrLaunchChrome(options: BrowserLaunchOptions?) async throws -> BrowserSessionInfo {
        attachRequests.append(options)
        return BrowserSessionInfo(
            debuggingPort: 9222,
            launched: true,
            tabCount: tabs.count,
            currentPage: currentPage,
            profile: profiles.first
        )
    }

    func listTabs() async throws -> [BrowserTabInfo] {
        listTabsCalls += 1
        return tabs
    }

    func selectTab(using selection: BrowserTabSelection) async throws -> BrowserTabInfo {
        selectedTabs.append(selection)
        return tabs.first ?? BrowserTabInfo(index: 0, title: currentPage.title, url: currentPage.url, isSelected: true, targetID: currentPage.targetID)
    }

    func goto(url: URL) async throws -> BrowserPageState {
        navigatedURLs.append(url)
        currentPage.url = url.absoluteString
        currentPage.title = "LinkedIn"
        return currentPage
    }

    func click(query: BrowserElementQuery) async throws -> BrowserPageState {
        clickedQueries.append(query)
        return currentPage
    }

    func type(text: String, query: BrowserElementQuery, pressEnter: Bool) async throws -> BrowserPageState {
        typedValues.append((text: text, query: query, pressEnter: pressEnter))
        return currentPage
    }

    func press(key: String) async throws -> BrowserPageState {
        pressedKeys.append(key)
        return currentPage
    }

    func waitFor(_ condition: BrowserWaitCondition) async throws -> BrowserWaitResult {
        waitConditions.append(condition)
        return BrowserWaitResult(conditionDescription: condition.summary, page: currentPage)
    }

    func snapshot() async throws -> BrowserSnapshot {
        snapshotCalls += 1
        return BrowserSnapshot(page: currentPage, textExcerpt: "Example body text")
    }

    func getURL() async throws -> String {
        urlReads += 1
        return currentPage.url
    }

    func getTitle() async throws -> String {
        titleReads += 1
        return currentPage.title
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
        let expectedModel = try promptCatalog.loadPrompt(named: "execution_agent_openai").config.llm

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
                let content = firstTurn["content"] as? [[String: Any]],
                let promptText = content.first(where: { ($0["type"] as? String) == "input_text" })?["text"] as? String
            else {
                throw NSError(domain: "OpenAIComputerUseRunnerTests", code: 0)
            }

            #expect(model == expectedModel)
            #expect(tools.compactMap { $0["name"] as? String }.contains("browser_action"))
            #expect(tools.compactMap { $0["name"] as? String }.contains("desktop_action"))
            #expect(tools.compactMap { $0["name"] as? String }.contains("terminal_exec"))
            #expect(content.contains(where: { ($0["type"] as? String) == "input_image" }))
            #expect(promptText.contains("CURRENT_CURSOR: (300, 200)"))
            #expect(promptText.contains("COORDINATE_SYSTEM: All screenshot and action coordinates use the selected display coordinate system"))

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
                try Self.makeValidScreenshot()
            },
            cursorPositionProvider: { (300, 200) }
        )
        let executor = OpenAIMockDesktopExecutor()

        let result = try await runner.runToolLoop(taskMarkdown: "# Task\nType hello world", executor: executor)

        #expect(result.outcome == .success)
        #expect(result.generatedQuestions.isEmpty)
        #expect(result.executedSteps.contains("Type text 'hello world'"))
        #expect(result.llmSummary == "Task completed")
        #expect(executor.typedTexts == ["hello world"])
        #expect(executor.moves.first == OpenAIXY(x: 640, y: 400))
        #expect(executor.clicks.first == OpenAIXY(x: 640, y: 400))
    }

    @Test
    func runToolLoopExecutesBrowserActionAndReturnsSuccess() async throws {
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
                  "name": "browser_action",
                  "arguments": "{\\"action\\":\\"goto\\",\\"url\\":\\"https://www.linkedin.com\\"}"
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
                throw NSError(domain: "OpenAIComputerUseRunnerTests", code: 98)
            }

            #expect(output.contains("\"ok\":true"))
            #expect(output.contains("linkedin.com"))

            let responseBody = """
            {
              "id": "resp_2",
              "output": [
                {
                  "type": "message",
                  "content": [
                    {
                      "type": "output_text",
                      "text": "{\\"status\\":\\"SUCCESS\\",\\"summary\\":\\"Browser navigation complete\\",\\"verification_status\\":\\"not_needed\\",\\"evidence\\":\\"DOM navigation succeeded via browser_action.\\",\\"error\\":null,\\"questions\\":[]}"
                    }
                  ]
                }
              ]
            }
            """
            return (Self.response(url: request.url!, code: 200), Data(responseBody.utf8))
        }

        let browserExecutor = OpenAIMockBrowserExecutor()
        let runner = OpenAIComputerUseRunner(
            apiKeyStore: OpenAIStubAPIKeyStore(values: [.openAI: "openai-test-key"]),
            promptCatalog: promptCatalog,
            session: makeSession(),
            browserExecutor: browserExecutor,
            screenshotProvider: {
                try Self.makeValidScreenshot()
            },
            cursorPositionProvider: { (300, 200) }
        )

        let result = try await runner.runToolLoop(taskMarkdown: "# Task\nGo to LinkedIn", executor: OpenAIMockDesktopExecutor())

        #expect(result.outcome == .success)
        #expect(result.llmSummary?.contains("Browser navigation complete") == true)
        #expect(browserExecutor.navigatedURLs == [URL(string: "https://www.linkedin.com")!])
    }

    @Test
    func runToolLoopPassesBrowserProfileHintIntoAttachAction() async throws {
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
                  "name": "browser_action",
                  "arguments": "{\\"action\\":\\"attach_or_launch_chrome\\",\\"profile_hint\\":\\"Farzam profile\\"}"
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
                throw NSError(domain: "OpenAIComputerUseRunnerTests", code: 97)
            }

            #expect(output.contains("\"ok\":true"))
            #expect(output.contains("Farzam Hejazi"))

            let responseBody = """
            {
              "id": "resp_2",
              "output": [
                {
                  "type": "message",
                  "content": [
                    {
                      "type": "output_text",
                      "text": "{\\"status\\":\\"SUCCESS\\",\\"summary\\":\\"Attached to requested browser profile\\",\\"verification_status\\":\\"not_needed\\",\\"evidence\\":\\"Browser attached with the resolved profile metadata.\\",\\"error\\":null,\\"questions\\":[]}"
                    }
                  ]
                }
              ]
            }
            """
            return (Self.response(url: request.url!, code: 200), Data(responseBody.utf8))
        }

        let browserExecutor = OpenAIMockBrowserExecutor()
        let runner = OpenAIComputerUseRunner(
            apiKeyStore: OpenAIStubAPIKeyStore(values: [.openAI: "openai-test-key"]),
            promptCatalog: promptCatalog,
            session: makeSession(),
            browserExecutor: browserExecutor,
            screenshotProvider: {
                try Self.makeValidScreenshot()
            },
            cursorPositionProvider: { (300, 200) }
        )

        let result = try await runner.runToolLoop(
            taskMarkdown: """
            # Task
            Open LinkedIn in Chrome.

            - [x] Which browser profile should be used?
              Answer: Farzam profile
            """,
            executor: OpenAIMockDesktopExecutor()
        )

        #expect(result.outcome == .success)
        #expect(browserExecutor.attachRequests.count == 1)
        #expect(browserExecutor.attachRequests.first??.profileHint == "Farzam profile")
    }

    @Test
    func runToolLoopUsesWebSocketTransportAndSendsIncrementalInputs() async throws {
        let (promptCatalog, tempRoot) = try makePromptCatalog()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let expectedModel = try promptCatalog.loadPrompt(named: "execution_agent_openai").config.llm

        let socket = OpenAITestWebSocket(
            incomingMessages: [
                .success("""
                {"type":"response.created","response":{"id":"resp_1"}}
                """),
                .success("""
                {"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","id":"fc_1","call_id":"call_1","name":"desktop_action"}}
                """),
                .success("""
                {"type":"response.function_call_arguments.delta","output_index":0,"delta":"{\\"action\\":\\"type\\","}
                """),
                .success("""
                {"type":"response.function_call_arguments.done","output_index":0,"arguments":"{\\"action\\":\\"type\\",\\"text\\":\\"hello via ws\\"}"}
                """),
                .success("""
                {"type":"response.completed","response":{"id":"resp_1"}}
                """),
                .success("""
                {"type":"response.created","response":{"id":"resp_2"}}
                """),
                .success("""
                {"type":"response.completed","response":{"id":"resp_2","output_text":"{\\"status\\":\\"SUCCESS\\",\\"summary\\":\\"Task completed\\",\\"error\\":null,\\"questions\\":[]}"}}
                """)
            ]
        )
        let connector = OpenAITestWebSocketConnector(connectResults: [.success(socket)])

        let runner = OpenAIComputerUseRunner(
            apiKeyStore: OpenAIStubAPIKeyStore(values: [.openAI: "openai-test-key"]),
            promptCatalog: promptCatalog,
            session: makeSession(),
            transportMode: .webSocketOnly,
            webSocketConnector: connector,
            screenshotProvider: {
                try Self.makeValidScreenshot()
            },
            cursorPositionProvider: { (300, 200) }
        )
        let executor = OpenAIMockDesktopExecutor()

        let result = try await runner.runToolLoop(taskMarkdown: "# Task\nType hello via ws", executor: executor)

        #expect(result.outcome == .success)
        #expect(executor.typedTexts == ["hello via ws"])
        #expect(connector.connectCount == 1)
        #expect(socket.sentTexts.count == 2)

        guard
            let firstPayloadData = socket.sentTexts.first?.data(using: .utf8),
            let firstPayload = try JSONSerialization.jsonObject(with: firstPayloadData) as? [String: Any],
            let firstInput = firstPayload["input"] as? [[String: Any]],
            let firstMessage = firstInput.first,
            let firstContent = firstMessage["content"] as? [[String: Any]]
        else {
            Issue.record("Missing first WebSocket payload.")
            return
        }

        #expect(firstPayload["type"] as? String == "response.create")
        #expect(firstPayload["model"] as? String == expectedModel)
        #expect((firstPayload["tools"] as? [[String: Any]])?.count == 3)
        #expect(firstPayload["previous_response_id"] == nil)
        #expect(firstContent.contains(where: { ($0["type"] as? String) == "input_image" }))
        let promptText = firstContent.first(where: { ($0["type"] as? String) == "input_text" })?["text"] as? String
        #expect(promptText?.contains("CURRENT_CURSOR: (300, 200)") == true)

        guard
            let secondPayloadData = socket.sentTexts.last?.data(using: .utf8),
            let secondPayload = try JSONSerialization.jsonObject(with: secondPayloadData) as? [String: Any],
            let secondInput = secondPayload["input"] as? [[String: Any]],
            let functionOutput = secondInput.first(where: { ($0["type"] as? String) == "function_call_output" })
        else {
            Issue.record("Missing second WebSocket payload.")
            return
        }

        #expect(secondPayload["previous_response_id"] as? String == "resp_1")
        #expect(functionOutput["call_id"] as? String == "call_1")
        #expect((functionOutput["output"] as? String)?.contains("\"ok\":true") == true)
    }

    @Test
    func runToolLoopUsesSelectedDisplayCoordinatesWhenScreenshotDownscaled() async throws {
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
            guard
                let bodyData = Self.requestBodyData(from: request),
                let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                let input = json["input"] as? [[String: Any]],
                let functionOutput = input.first(where: { ($0["type"] as? String) == "function_call_output" }),
                let output = functionOutput["output"] as? String
            else {
                throw NSError(domain: "OpenAIComputerUseRunnerTests", code: 2)
            }

            #expect(output.contains("\"verification_required\":true"))
            #expect(output.contains("\"action_state\":\"injected_pending_verification\""))

            let responseBody = """
            {
              "id": "resp_2",
              "output": [
                {
                  "type": "message",
                  "content": [
                    {
                      "type": "output_text",
                      "text": "{\\"status\\":\\"SUCCESS\\",\\"summary\\":\\"ok\\",\\"verification_status\\":\\"verified\\",\\"evidence\\":\\"The clicked target is visibly focused in the latest screenshot.\\",\\"error\\":null,\\"questions\\":[]}"
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
                let data = try Self.makeValidPNGData(width: 8, height: 8)
                return OpenAICapturedScreenshot(
                    width: 1280,
                    height: 720,
                    captureWidthPx: 2560,
                    captureHeightPx: 1440,
                    coordinateSpaceWidthPx: 2560,
                    coordinateSpaceHeightPx: 1440,
                    coordinateSpaceOriginX: 0,
                    coordinateSpaceOriginY: 0,
                    mediaType: "image/png",
                    base64Data: data.base64EncodedString(),
                    byteCount: data.count
                )
            }
        )
        let executor = OpenAIMockDesktopExecutor()

        let result = try await runner.runToolLoop(taskMarkdown: "# Task\nClick target", executor: executor)
        #expect(result.outcome == .success)
        #expect(result.llmSummary?.contains("Verification status: verified") == true)
        #expect(executor.clicks.last == OpenAIXY(x: 100, y: 200))
    }

    @Test
    func runToolLoopDowngradesSuccessWhenVisualClickLacksVerificationEvidence() async throws {
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
                try Self.makeValidScreenshot()
            }
        )
        let executor = OpenAIMockDesktopExecutor()

        let result = try await runner.runToolLoop(taskMarkdown: "# Task\nClick target", executor: executor)

        #expect(result.outcome == .needsClarification)
        #expect(result.errorMessage?.contains("was not verified before SUCCESS") == true)
        #expect(result.generatedQuestions.contains(where: { $0.contains("still needs screenshot-based verification") }))
        #expect(executor.clicks.last == OpenAIXY(x: 100, y: 200))
    }

    @Test
    func runToolLoopExecutesMouseMoveExecution() async throws {
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
                  "arguments": "{\\"action\\":\\"mouse_move\\",\\"x\\":900,\\"y\\":700}"
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
                throw NSError(domain: "OpenAIComputerUseRunnerTests", code: 90)
            }

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
                try Self.makeValidScreenshot()
            }
        )
        let executor = OpenAIMockDesktopExecutor()

        let result = try await runner.runToolLoop(taskMarkdown: "# Task\nMove the mouse", executor: executor)

        #expect(result.outcome == .success)
        #expect(result.executedSteps.contains("Move mouse to (900, 700)"))
        #expect(executor.moves == [OpenAIXY(x: 640, y: 400), OpenAIXY(x: 900, y: 700)])
    }

    @Test
    func runToolLoopFallsBackToHTTPWhenWebSocketConnectFails() async throws {
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
                  "arguments": "{\\"action\\":\\"type\\",\\"text\\":\\"fallback hello\\"}"
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

        let connector = OpenAITestWebSocketConnector(
            connectResults: [.failure(URLError(.cannotConnectToHost))]
        )

        let runner = OpenAIComputerUseRunner(
            apiKeyStore: OpenAIStubAPIKeyStore(values: [.openAI: "openai-test-key"]),
            promptCatalog: promptCatalog,
            session: makeSession(),
            transportMode: .webSocketPreferred,
            webSocketConnector: connector,
            screenshotProvider: {
                try Self.makeValidScreenshot()
            }
        )
        let executor = OpenAIMockDesktopExecutor()

        let result = try await runner.runToolLoop(taskMarkdown: "# Task\nType fallback hello", executor: executor)

        #expect(result.outcome == .success)
        #expect(executor.typedTexts == ["fallback hello"])
        #expect(connector.connectCount == 1)
        #expect(OpenAIQueueURLProtocol.capturedRequests.count == 2)
    }

    @Test
    func runToolLoopFallsBackToHTTPWhenWebSocketLosesPreviousResponseState() async throws {
        let (promptCatalog, tempRoot) = try makePromptCatalog()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        OpenAIQueueURLProtocol.reset()
        defer { OpenAIQueueURLProtocol.reset() }

        OpenAIQueueURLProtocol.enqueue { request in
            guard
                let bodyData = Self.requestBodyData(from: request),
                let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                let previousResponseId = json["previous_response_id"] as? String,
                let input = json["input"] as? [[String: Any]],
                let functionOutput = input.first(where: { ($0["type"] as? String) == "function_call_output" })
            else {
                throw NSError(domain: "OpenAIComputerUseRunnerTests", code: 301)
            }

            #expect(previousResponseId == "resp_1")
            #expect(functionOutput["call_id"] as? String == "call_1")

            let responseBody = """
            {
              "id": "resp_http_2",
              "output": [
                {
                  "type": "message",
                  "content": [
                    {
                      "type": "output_text",
                      "text": "{\\"status\\":\\"SUCCESS\\",\\"summary\\":\\"fallback ok\\",\\"error\\":null,\\"questions\\":[]}"
                    }
                  ]
                }
              ]
            }
            """
            return (Self.response(url: request.url!, code: 200), Data(responseBody.utf8))
        }

        let socket = OpenAITestWebSocket(
            incomingMessages: [
                .success("""
                {"type":"response.created","response":{"id":"resp_1"}}
                """),
                .success("""
                {"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","id":"fc_1","call_id":"call_1","name":"desktop_action","arguments":"{\\"action\\":\\"type\\",\\"text\\":\\"ws first turn\\"}"}}
                """),
                .success("""
                {"type":"response.completed","response":{"id":"resp_1"}}
                """),
                .success("""
                {"type":"error","status":400,"error":{"code":"previous_response_not_found","message":"Previous response with id 'resp_1' not found.","type":"invalid_request_error"}}
                """)
            ]
        )
        let connector = OpenAITestWebSocketConnector(connectResults: [.success(socket)])

        let runner = OpenAIComputerUseRunner(
            apiKeyStore: OpenAIStubAPIKeyStore(values: [.openAI: "openai-test-key"]),
            promptCatalog: promptCatalog,
            session: makeSession(),
            transportMode: .webSocketPreferred,
            webSocketConnector: connector,
            screenshotProvider: {
                try Self.makeValidScreenshot()
            }
        )
        let executor = OpenAIMockDesktopExecutor()

        let result = try await runner.runToolLoop(taskMarkdown: "# Task\nType ws first turn", executor: executor)

        #expect(result.outcome == .success)
        #expect(executor.typedTexts == ["ws first turn"])
        #expect(connector.connectCount == 1)
        #expect(OpenAIQueueURLProtocol.capturedRequests.count == 1)
    }

    @Test
    func runToolLoopReconnectsWebSocketAfterConnectionLimitError() async throws {
        let (promptCatalog, tempRoot) = try makePromptCatalog()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let firstSocket = OpenAITestWebSocket(
            incomingMessages: [
                .success("""
                {"type":"error","status":400,"error":{"code":"websocket_connection_limit_reached","message":"Responses websocket connection limit reached (60 minutes). Create a new websocket connection to continue.","type":"invalid_request_error"}}
                """)
            ]
        )
        let secondSocket = OpenAITestWebSocket(
            incomingMessages: [
                .success("""
                {"type":"response.created","response":{"id":"resp_ws_2"}}
                """),
                .success("""
                {"type":"response.completed","response":{"id":"resp_ws_2","output_text":"{\\"status\\":\\"SUCCESS\\",\\"summary\\":\\"reconnected\\",\\"error\\":null,\\"questions\\":[]}"}}
                """)
            ]
        )
        let connector = OpenAITestWebSocketConnector(
            connectResults: [.success(firstSocket), .success(secondSocket)]
        )

        let runner = OpenAIComputerUseRunner(
            apiKeyStore: OpenAIStubAPIKeyStore(values: [.openAI: "openai-test-key"]),
            promptCatalog: promptCatalog,
            session: makeSession(),
            transportMode: .webSocketOnly,
            webSocketConnector: connector,
            screenshotProvider: {
                try Self.makeValidScreenshot()
            }
        )

        let result = try await runner.runToolLoop(taskMarkdown: "# Task\nReturn success", executor: OpenAIMockDesktopExecutor())

        #expect(result.outcome == .success)
        #expect(result.llmSummary == "reconnected")
        #expect(connector.connectCount == 2)
        #expect(firstSocket.sentTexts.count == 1)
        #expect(secondSocket.sentTexts.count == 1)
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
                try Self.makeValidScreenshot()
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
                try Self.makeValidScreenshot()
            }
        )

        let result = try await runner.runToolLoop(taskMarkdown: "# Task", executor: OpenAIMockDesktopExecutor())
        #expect(result.outcome == .success)
        #expect(result.executedSteps.contains(where: { $0.contains("Terminal exec:") }) == false)
    }

    @Test
    func runToolLoopRejectsTerminalOpenCommandAndRequestsDesktopActionTool() async throws {
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
                  "arguments": "{\\"executable\\":\\"open\\",\\"args\\":[\\"-a\\",\\"Google Chrome\\"]}"
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
                throw NSError(domain: "OpenAIComputerUseRunnerTests", code: 19)
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
                try Self.makeValidScreenshot()
            }
        )

        let result = try await runner.runToolLoop(taskMarkdown: "# Task", executor: OpenAIMockDesktopExecutor())
        #expect(result.outcome == .success)
        #expect(result.executedSteps.contains(where: { $0.contains("Terminal exec:") }) == false)
    }

    @Test
    func runToolLoopRejectsCmdTabShortcutAndRequestsOpenAppAction() async throws {
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
                  "arguments": "{\\"action\\":\\"key\\",\\"key\\":\\"cmd+tab\\"}"
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
                throw NSError(domain: "OpenAIComputerUseRunnerTests", code: 20)
            }

            #expect(output.contains("\"ok\":false"))
            #expect(output.contains("\"error\":\"policy_violation\""))
            #expect(output.contains("Use action 'open_app'"))

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
                try Self.makeValidScreenshot()
            }
        )
        let executor = OpenAIMockDesktopExecutor()

        let result = try await runner.runToolLoop(taskMarkdown: "# Task", executor: executor)
        #expect(result.outcome == .success)
        #expect(executor.shortcuts.isEmpty)
        #expect(result.executedSteps.contains(where: { $0.contains("Press shortcut") }) == false)
    }

    @Test
    func runToolLoopPrimesDisplayBeforeCmdSpaceShortcut() async throws {
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
                  "arguments": "{\\"action\\":\\"key\\",\\"key\\":\\"cmd+space\\"}"
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
                throw NSError(domain: "OpenAIComputerUseRunnerTests", code: 30)
            }

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
                try Self.makeValidScreenshot()
            }
        )
        let executor = OpenAIMockDesktopExecutor()

        let result = try await runner.runToolLoop(taskMarkdown: "# Task", executor: executor)
        #expect(result.outcome == .success)
        #expect(executor.shortcuts.count == 1)
        #expect(executor.shortcuts.first?.key == " ")
        #expect(executor.shortcuts.first?.command == true)
        #expect(Array(executor.moves.prefix(2)) == [OpenAIXY(x: 640, y: 400), OpenAIXY(x: 640, y: 400)])
        #expect(Array(executor.clicks.prefix(2)) == [OpenAIXY(x: 640, y: 400), OpenAIXY(x: 640, y: 400)])
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
                try Self.makeValidScreenshot()
            }
        )

        let result = try await runner.runToolLoop(taskMarkdown: "# Task", executor: OpenAIMockDesktopExecutor())
        #expect(result.outcome == .success)
        #expect(result.executedSteps.contains(where: { $0.contains("Terminal exec: true") }))
    }

    @Test
    func runToolLoopMapsInvalidCredentialsToUserFacingIssue() async throws {
        let (promptCatalog, tempRoot) = try makePromptCatalog()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        OpenAIQueueURLProtocol.reset()
        defer { OpenAIQueueURLProtocol.reset() }

        OpenAIQueueURLProtocol.enqueue { request in
            let body = """
            {"error":{"message":"Incorrect API key provided","type":"invalid_request_error","code":"invalid_api_key"}}
            """
            return (Self.response(url: request.url!, code: 401), Data(body.utf8))
        }

        let runner = OpenAIComputerUseRunner(
            apiKeyStore: OpenAIStubAPIKeyStore(values: [.openAI: "openai-test-key"]),
            promptCatalog: promptCatalog,
            session: makeSession(),
            screenshotProvider: {
                try Self.makeValidScreenshot()
            }
        )

        do {
            _ = try await runner.runToolLoop(taskMarkdown: "# Task", executor: OpenAIMockDesktopExecutor())
            #expect(Bool(false))
        } catch let error as OpenAIExecutionPlannerError {
            guard case .userFacingIssue(let issue) = error else {
                #expect(Bool(false))
                return
            }
            #expect(issue.kind == .invalidCredentials)
            #expect(issue.provider == .openAI)
            #expect(issue.operation == .execution)
            #expect(issue.httpStatus == 401)
        }
    }

    @Test
    func runToolLoopMapsQuotaErrorsToUserFacingIssue() async throws {
        let (promptCatalog, tempRoot) = try makePromptCatalog()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        OpenAIQueueURLProtocol.reset()
        defer { OpenAIQueueURLProtocol.reset() }

        OpenAIQueueURLProtocol.enqueue { request in
            let body = """
            {"error":{"message":"You exceeded your current quota, please check your plan and billing details.","type":"insufficient_quota","code":"insufficient_quota"}}
            """
            return (Self.response(url: request.url!, code: 429), Data(body.utf8))
        }

        let runner = OpenAIComputerUseRunner(
            apiKeyStore: OpenAIStubAPIKeyStore(values: [.openAI: "openai-test-key"]),
            promptCatalog: promptCatalog,
            session: makeSession(),
            screenshotProvider: {
                try Self.makeValidScreenshot()
            }
        )

        do {
            _ = try await runner.runToolLoop(taskMarkdown: "# Task", executor: OpenAIMockDesktopExecutor())
            #expect(Bool(false))
        } catch let error as OpenAIExecutionPlannerError {
            guard case .userFacingIssue(let issue) = error else {
                #expect(Bool(false))
                return
            }
            #expect(issue.kind == .quotaOrBudgetExhausted)
            #expect(issue.provider == .openAI)
            #expect(issue.operation == .execution)
            #expect(issue.httpStatus == 429)
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
        config.protocolClasses = [OpenAIQueueURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makePromptCatalog() throws -> (PromptCatalogService, URL) {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try TestPromptFixtureSupport.writePromptFixture(
            named: "execution_agent_openai",
            into: tempRoot,
            promptBody: """
            PROMPT_HEADER
            OS: {{OS_VERSION}}
            SCREEN_WIDTH: {{SCREEN_WIDTH}}
            SCREEN_HEIGHT: {{SCREEN_HEIGHT}}
            TASK_MARKDOWN:
            {{TASK_MARKDOWN}}
            PROMPT_FOOTER
            """,
            fileManager: fm
        )

        return (PromptCatalogService(promptsRootURL: tempRoot, fileManager: fm), tempRoot)
    }

    private static func makeValidPNGData(width: Int, height: Int) throws -> Data {
        guard
            let bitmapRep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ),
            let context = NSGraphicsContext(bitmapImageRep: bitmapRep)
        else {
            throw NSError(domain: "OpenAIComputerUseRunnerTests", code: 201)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(calibratedWhite: 0.92, alpha: 1.0).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "OpenAIComputerUseRunnerTests", code: 202)
        }
        return pngData
    }

    private static func makeValidScreenshot(
        width: Int = 1280,
        height: Int = 800,
        captureWidthPx: Int = 1280,
        captureHeightPx: Int = 800,
        coordinateSpaceWidthPx: Int = 1280,
        coordinateSpaceHeightPx: Int = 800,
        coordinateSpaceOriginX: Int = 0,
        coordinateSpaceOriginY: Int = 0
    ) throws -> OpenAICapturedScreenshot {
        let data = try makeValidPNGData(width: max(1, min(width, 64)), height: max(1, min(height, 64)))
        return OpenAICapturedScreenshot(
            width: width,
            height: height,
            captureWidthPx: captureWidthPx,
            captureHeightPx: captureHeightPx,
            coordinateSpaceWidthPx: coordinateSpaceWidthPx,
            coordinateSpaceHeightPx: coordinateSpaceHeightPx,
            coordinateSpaceOriginX: coordinateSpaceOriginX,
            coordinateSpaceOriginY: coordinateSpaceOriginY,
            mediaType: "image/png",
            base64Data: data.base64EncodedString(),
            byteCount: data.count
        )
    }
}
