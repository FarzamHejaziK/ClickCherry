import AppKit
import Foundation
import Testing
@testable import TaskAgentMacOSApp

private final class OpenAIMCPStubAPIKeyStore: APIKeyStore {
    private let values: [ProviderIdentifier: String]

    init(values: [ProviderIdentifier: String]) {
        self.values = values
    }

    func hasKey(for provider: ProviderIdentifier) -> Bool {
        guard let value = values[provider] else { return false }
        return !value.isEmpty
    }

    func readKey(for provider: ProviderIdentifier) throws -> String? {
        values[provider]
    }

    func setKey(_ key: String?, for provider: ProviderIdentifier) throws {}
}

private final class OpenAIMCPQueueURLProtocol: URLProtocol {
    static let lock = NSLock()
    static var handlers: [((URLRequest) throws -> (HTTPURLResponse, Data))] = []

    static func reset() {
        lock.lock()
        handlers = []
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
        Self.lock.lock()
        let handler = Self.handlers.isEmpty ? nil : Self.handlers.removeFirst()
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "OpenAIMCPQueueURLProtocol", code: -1))
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

private final class OpenAIMCPMockDesktopExecutor: DesktopActionExecutor {
    func openApp(named appName: String) throws {}
    func openURL(_ url: URL) throws {}
    func sendShortcut(key: String, command: Bool, option: Bool, control: Bool, shift: Bool) throws {}
    func typeText(_ text: String) throws {}
    func click(x: Int, y: Int) throws {}
    func moveMouse(x: Int, y: Int) throws {}
    func rightClick(x: Int, y: Int) throws {}
    func scroll(deltaX: Int, deltaY: Int) throws {}
}

private actor OpenAIMCPFakeServerManager: MCPServerManaging {
    let preparedTools: MCPPreparedTools
    let callResult: MCPToolResult?
    let callError: Error?
    private(set) var prepareForRunCount = 0
    private(set) var calledTools: [MCPToolCall] = []

    init(preparedTools: MCPPreparedTools, callResult: MCPToolResult? = nil, callError: Error? = nil) {
        self.preparedTools = preparedTools
        self.callResult = callResult
        self.callError = callError
    }

    func prepareForRun() async -> MCPPreparedTools {
        prepareForRunCount += 1
        return preparedTools
    }

    func callTool(named toolName: String, arguments: MCPValue?) async throws -> MCPToolResult {
        calledTools.append(MCPToolCall(serverID: "playwright_mcp_extension", toolName: toolName, arguments: arguments))
        if let callError {
            throw callError
        }
        guard let callResult else {
            throw MCPRuntimeError.toolNotFound(toolName)
        }
        return callResult
    }
}

@Suite(.serialized)
@MainActor
struct OpenAIComputerUseRunnerMCPTests {
    @Test
    func runToolLoopIncludesMCPDiscoveredToolsInInitialRequest() async throws {
        let (promptCatalog, tempRoot) = try makePromptCatalog()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let prepared = MCPPreparedTools(
            tools: [
                MCPToolDefinition(
                    serverID: "playwright_mcp_extension",
                    name: "browser_snapshot",
                    description: "Capture an accessibility snapshot of the current page.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "kind": .object(["type": .string("string")])
                        ]),
                        "additionalProperties": .bool(false)
                    ])
                )
            ],
            serverStatuses: [
                MCPServerStatus(
                    serverID: "playwright_mcp_extension",
                    displayName: "Playwright MCP Bridge",
                    state: .connected
                )
            ]
        )
        let mcpManager = OpenAIMCPFakeServerManager(preparedTools: prepared)

        OpenAIMCPQueueURLProtocol.reset()
        defer { OpenAIMCPQueueURLProtocol.reset() }

        OpenAIMCPQueueURLProtocol.enqueue { request in
            let json = try Self.decodeRequestJSON(request)
            let tools = (json["tools"] as? [[String: Any]]) ?? []
            let toolNames = tools.compactMap { $0["name"] as? String }
            #expect(toolNames.contains("desktop_action"))
            #expect(toolNames.contains("terminal_exec"))
            #expect(toolNames.contains("browser_snapshot"))

            let input = (json["input"] as? [[String: Any]]) ?? []
            let firstTurn = input.first ?? [:]
            let content = (firstTurn["content"] as? [[String: Any]]) ?? []
            let promptText = content.first(where: { ($0["type"] as? String) == "input_text" })?["text"] as? String ?? ""
            #expect(promptText.contains("MCP_RUNTIME_STATUS:"))
            #expect(promptText.contains("AVAILABLE_MCP_TOOLS:"))
            #expect(promptText.contains("browser_snapshot"))

            let responseBody = """
            {
              "id": "resp_mcp_1",
              "output": [
                {
                  "type": "message",
                  "content": [
                    {
                      "type": "output_text",
                      "text": "{\\"status\\":\\"SUCCESS\\",\\"summary\\":\\"MCP tools available\\",\\"verification_status\\":\\"not_needed\\",\\"evidence\\":\\"Browser MCP tool list exposed to the model.\\",\\"error\\":null,\\"questions\\":[]}"
                    }
                  ]
                }
              ]
            }
            """
            return (Self.response(url: request.url!, code: 200), Data(responseBody.utf8))
        }

        let runner = OpenAIComputerUseRunner(
            apiKeyStore: OpenAIMCPStubAPIKeyStore(values: [.openAI: "openai-test-key"]),
            promptCatalog: promptCatalog,
            session: makeSession(),
            mcpServerManager: mcpManager,
            screenshotProvider: { try Self.makeValidScreenshot() },
            cursorPositionProvider: { (320, 240) }
        )

        let result = try await runner.runToolLoop(taskMarkdown: "# Task\nInspect the current webpage", executor: OpenAIMCPMockDesktopExecutor())

        #expect(result.outcome == .success)
        #expect(result.llmSummary == "MCP tools available\nVerification status: not_needed\nEvidence: Browser MCP tool list exposed to the model.")
        #expect(await mcpManager.prepareForRunCount == 1)
    }

    @Test
    func runToolLoopRoutesMCPFunctionCallsThroughServerManager() async throws {
        let (promptCatalog, tempRoot) = try makePromptCatalog()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let prepared = MCPPreparedTools(
            tools: [
                MCPToolDefinition(
                    serverID: "playwright_mcp_extension",
                    name: "browser_snapshot",
                    description: "Capture an accessibility snapshot of the current page.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([:]),
                        "additionalProperties": .bool(true)
                    ])
                )
            ],
            serverStatuses: [
                MCPServerStatus(
                    serverID: "playwright_mcp_extension",
                    displayName: "Playwright MCP Bridge",
                    state: .connected
                )
            ]
        )
        let toolResult = MCPToolResult(
            serverID: "playwright_mcp_extension",
            toolName: "browser_snapshot",
            value: .object([
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("fake snapshot")
                    ])
                ]),
                "isError": .bool(false)
            ]),
            isError: false
        )
        let mcpManager = OpenAIMCPFakeServerManager(preparedTools: prepared, callResult: toolResult)

        OpenAIMCPQueueURLProtocol.reset()
        defer { OpenAIMCPQueueURLProtocol.reset() }

        OpenAIMCPQueueURLProtocol.enqueue { request in
            let json = try Self.decodeRequestJSON(request)
            let toolNames = ((json["tools"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
            #expect(toolNames.contains("browser_snapshot"))

            let responseBody = """
            {
              "id": "resp_1",
              "output": [
                {
                  "type": "function_call",
                  "id": "fc_browser_1",
                  "call_id": "call_browser_1",
                  "name": "browser_snapshot",
                  "arguments": "{\\"kind\\":\\"dom\\"}"
                }
              ]
            }
            """
            return (Self.response(url: request.url!, code: 200), Data(responseBody.utf8))
        }

        OpenAIMCPQueueURLProtocol.enqueue { request in
            let json = try Self.decodeRequestJSON(request)
            #expect(json["previous_response_id"] as? String == "resp_1")

            let input = (json["input"] as? [[String: Any]]) ?? []
            let functionOutput = input.first(where: { ($0["type"] as? String) == "function_call_output" }) ?? [:]
            #expect(functionOutput["call_id"] as? String == "call_browser_1")

            let output = functionOutput["output"] as? String ?? ""
            #expect(output.contains("fake snapshot"))
            #expect(output.contains("\"isError\":false") || output.contains("\"isError\": false"))

            let responseBody = """
            {
              "id": "resp_2",
              "output": [
                {
                  "type": "message",
                  "content": [
                    {
                      "type": "output_text",
                      "text": "{\\"status\\":\\"SUCCESS\\",\\"summary\\":\\"Browser snapshot captured\\",\\"verification_status\\":\\"not_needed\\",\\"evidence\\":\\"MCP tool output returned successfully.\\",\\"error\\":null,\\"questions\\":[]}"
                    }
                  ]
                }
              ]
            }
            """
            return (Self.response(url: request.url!, code: 200), Data(responseBody.utf8))
        }

        let runner = OpenAIComputerUseRunner(
            apiKeyStore: OpenAIMCPStubAPIKeyStore(values: [.openAI: "openai-test-key"]),
            promptCatalog: promptCatalog,
            session: makeSession(),
            mcpServerManager: mcpManager,
            screenshotProvider: { try Self.makeValidScreenshot() },
            cursorPositionProvider: { (320, 240) }
        )

        let result = try await runner.runToolLoop(taskMarkdown: "# Task\nInspect the current webpage", executor: OpenAIMCPMockDesktopExecutor())

        #expect(result.outcome == .success)
        let calledTools = await mcpManager.calledTools
        #expect(calledTools.count == 1)
        #expect(calledTools.first?.toolName == "browser_snapshot")
        #expect(calledTools.first?.arguments == .object(["kind": .string("dom")]))
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAIMCPQueueURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makePromptCatalog() throws -> (PromptCatalogService, URL) {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try TestPromptFixtureSupport.writePromptFixture(
            named: "execution_agent_openai",
            into: tempRoot,
            promptBody: "You are an execution agent.\nTASK_MARKDOWN:\n{{TASK_MARKDOWN}}"
        )
        return (PromptCatalogService(promptsRootURL: tempRoot), tempRoot)
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
            throw NSError(domain: "OpenAIComputerUseRunnerMCPTests", code: 201)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(calibratedWhite: 0.94, alpha: 1.0).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "OpenAIComputerUseRunnerMCPTests", code: 202)
        }
        return pngData
    }

    private static func makeValidScreenshot() throws -> OpenAICapturedScreenshot {
        let pngData = try makeValidPNGData(width: 64, height: 64)
        return OpenAICapturedScreenshot(
            width: 1280,
            height: 800,
            captureWidthPx: 1280,
            captureHeightPx: 800,
            coordinateSpaceWidthPx: 1280,
            coordinateSpaceHeightPx: 800,
            coordinateSpaceOriginX: 0,
            coordinateSpaceOriginY: 0,
            mediaType: "image/png",
            base64Data: pngData.base64EncodedString(),
            byteCount: pngData.count
        )
    }

    private static func response(url: URL, code: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
    }

    private static func decodeRequestJSON(_ request: URLRequest) throws -> [String: Any] {
        if let body = request.httpBody {
            guard let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                throw NSError(domain: "OpenAIComputerUseRunnerMCPTests", code: 1)
            }
            return json
        }

        guard let bodyStream = request.httpBodyStream else {
            throw NSError(domain: "OpenAIComputerUseRunnerMCPTests", code: 0)
        }
        bodyStream.open()
        defer { bodyStream.close() }

        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        let data = NSMutableData()
        while bodyStream.hasBytesAvailable {
            let read = bodyStream.read(buffer, maxLength: bufferSize)
            if read < 0 {
                throw bodyStream.streamError ?? NSError(domain: "OpenAIComputerUseRunnerMCPTests", code: -1)
            }
            if read == 0 {
                break
            }
            data.append(buffer, length: read)
        }

        guard let json = try JSONSerialization.jsonObject(with: data as Data) as? [String: Any] else {
            throw NSError(domain: "OpenAIComputerUseRunnerMCPTests", code: 1)
        }
        return json
    }
}
