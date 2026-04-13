import Foundation

actor MCPServerSession {
    private static let protocolVersion = "2025-03-26"
    private static let maxDiagnostics = 12

    private let definition: MCPServerDefinition
    private var process: MCPServerProcess?
    private var client: MCPJSONRPCClient?
    private var tools: [MCPToolDefinition] = []
    private var status: MCPServerConnectionState = .notStarted
    private var diagnostics: [String] = []

    init(definition: MCPServerDefinition) {
        self.definition = definition
    }

    func ensureStarted() async throws {
        if case .connected = status, let client, !(await client.isDisconnected()) {
            return
        }

        status = .starting
        tools = []
        diagnostics = []

        do {
            let process = ensureProcess()
            let transport = try process.restart()
            recordDiagnostic("Launch command: \(process.launchCommandSummary)")
            if let resolvedExecutablePath = process.resolvedExecutablePath {
                recordDiagnostic("Resolved executable: \(resolvedExecutablePath)")
            }
            if hasConfiguredPlaywrightBridgeToken {
                recordDiagnostic("PLAYWRIGHT_MCP_EXTENSION_TOKEN is present in the MCP server environment.")
            } else if definition.id == "playwright_mcp_extension" {
                recordDiagnostic("PLAYWRIGHT_MCP_EXTENSION_TOKEN is not present; Playwright MCP Bridge will require interactive approval from the Chrome extension.")
            }
            let rpcClient = MCPJSONRPCClient(transport: transport, requestTimeout: definition.startupTimeout)
            await rpcClient.installTransportHandlers()
            self.client = rpcClient

            recordDiagnostic("Sending MCP initialize request.")
            let initializeResultValue = try await rpcClient.request(
                method: "initialize",
                params: .object([
                    "protocolVersion": .string(Self.protocolVersion),
                    "capabilities": .object([:]),
                    "clientInfo": .object([
                        "name": .string("ClickCherry"),
                        "version": .string("0.1")
                    ])
                ])
            )
            _ = try initializeResultValue.decode(MCPInitializeResult.self)
            recordDiagnostic("Received MCP initialize response.")

            recordDiagnostic("Sending MCP notifications/initialized event.")
            try await rpcClient.notify(method: "notifications/initialized", params: .object([:]))

            recordDiagnostic("Requesting MCP tools/list.")
            let listToolsValue = try await rpcClient.request(method: "tools/list", params: .object([:]))
            let listToolsResult = try listToolsValue.decode(MCPListToolsResult.self)
            tools = listToolsResult.tools.map { tool in
                MCPToolDefinition(
                    serverID: definition.id,
                    name: tool.name,
                    description: tool.description ?? "",
                    inputSchema: tool.inputSchema ?? .object([
                        "type": .string("object"),
                        "properties": .object([:]),
                        "additionalProperties": .bool(true)
                    ])
                )
            }

            mergeDiagnostics(await rpcClient.currentDiagnostics())
            recordDiagnostic("Received MCP tools/list response.")
            recordDiagnostic("Handshake completed and discovered \(tools.count) MCP tool(s).")
            status = .connected
        } catch {
            if let client {
                mergeDiagnostics(await client.currentDiagnostics())
            }
            self.client = nil
            process?.stop()
            let contextualizedError = contextualizeStartupError(error)
            status = .failed(contextualizedError.localizedDescription)
            throw contextualizedError
        }
    }

    func listTools() async throws -> [MCPToolDefinition] {
        try await ensureStarted()
        return tools
    }

    func callTool(name: String, arguments: MCPValue?) async throws -> MCPToolResult {
        try await ensureStarted()
        guard let client else {
            throw MCPRuntimeError.processNotStarted(definition.id)
        }

        do {
            let result = try await client.request(
                method: "tools/call",
                params: .object([
                    "name": .string(name),
                    "arguments": arguments ?? .object([:])
                ])
            )
            mergeDiagnostics(await client.currentDiagnostics())
            let isError = result.objectValue?["isError"]?.boolValue ?? false
            return MCPToolResult(serverID: definition.id, toolName: name, value: result, isError: isError)
        } catch {
            mergeDiagnostics(await client.currentDiagnostics())
            status = .disconnected(error.localizedDescription)
            process?.stop()
            self.client = nil
            throw error
        }
    }

    func currentStatus() -> MCPServerStatus {
        MCPServerStatus(
            serverID: definition.id,
            displayName: definition.displayName,
            state: status,
            diagnostics: diagnostics
        )
    }

    private func ensureProcess() -> MCPServerProcess {
        if let process {
            return process
        }
        let created = MCPServerProcess(definition: definition)
        process = created
        return created
    }

    private func contextualizeStartupError(_ error: Error) -> Error {
        let diagnosticsSummary = formattedDiagnosticsSummary()

        if let runtimeError = error as? MCPRuntimeError, case .processNotStarted = runtimeError {
            return MCPRuntimeError.serverFailedToStart(
                """
                MCP process exited before the initialize handshake completed.\(diagnosticsSummary)
                """
            )
        }

        if let runtimeError = error as? MCPRuntimeError,
           case .serverDisconnected(let message) = runtimeError,
           message.localizedCaseInsensitiveContains("EOF")
            || message.localizedCaseInsensitiveContains("Process exited")
        {
            return MCPRuntimeError.serverFailedToStart(
                """
                MCP process exited before the initialize handshake completed.\(diagnosticsSummary)
                """
            )
        }

        guard definition.id == "playwright_mcp_extension" else {
            if let runtimeError = error as? MCPRuntimeError, case .serverFailedToStart(let message) = runtimeError {
                return MCPRuntimeError.serverFailedToStart("\(message)\(diagnosticsSummary)")
            }
            return MCPRuntimeError.serverFailedToStart("\(error.localizedDescription)\(diagnosticsSummary)")
        }

        if case let MCPRuntimeError.requestTimedOut(method, seconds) = error {
            return MCPRuntimeError.serverFailedToStart(
                """
                Playwright MCP Bridge did not respond during '\(method)' after \(String(format: "%.1f", seconds)) seconds. \
                Open Chrome with the Playwright MCP Bridge extension enabled, approve the first connection if prompted, \
                and if you want ClickCherry to connect automatically save the bridge token in Settings > Model Setup > Browser Automation.\(diagnosticsSummary)
                """
            )
        }

        if case let MCPRuntimeError.serverDisconnected(message) = error {
            if message.localizedCaseInsensitiveContains("EOF")
                || message.localizedCaseInsensitiveContains("Process exited")
            {
                return MCPRuntimeError.serverFailedToStart(
                    """
                    Playwright MCP Bridge exited before the initialize handshake completed.\(diagnosticsSummary)
                    """
                )
            }
            return MCPRuntimeError.serverFailedToStart(
                """
                Playwright MCP Bridge disconnected during startup: \(message). \
                Ensure the extension is installed and the bridge page is connected in the same Chrome profile.\(diagnosticsSummary)
                """
            )
        }

        if let runtimeError = error as? MCPRuntimeError, case .serverFailedToStart(let message) = runtimeError {
            return MCPRuntimeError.serverFailedToStart("\(message)\(diagnosticsSummary)")
        }

        return MCPRuntimeError.serverFailedToStart("\(error.localizedDescription)\(diagnosticsSummary)")
    }

    private func recordDiagnostic(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        diagnostics.append(trimmed)
        if diagnostics.count > Self.maxDiagnostics {
            diagnostics.removeFirst(diagnostics.count - Self.maxDiagnostics)
        }
    }

    private func mergeDiagnostics(_ incoming: [String]) {
        for entry in incoming {
            guard !diagnostics.contains(entry) else { continue }
            recordDiagnostic(entry)
        }
    }

    private func formattedDiagnosticsSummary() -> String {
        guard !diagnostics.isEmpty else { return "" }
        let joined = diagnostics.joined(separator: " | ")
        return " Diagnostics: \(joined)"
    }

    private var hasConfiguredPlaywrightBridgeToken: Bool {
        if let token = definition.environment["PLAYWRIGHT_MCP_EXTENSION_TOKEN"],
           !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        if let rawToken = getenv("PLAYWRIGHT_MCP_EXTENSION_TOKEN"),
           let token = String(validatingUTF8: rawToken),
           !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        return false
    }
}
