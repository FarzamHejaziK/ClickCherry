import Foundation

extension OpenAIComputerUseRunner {
    private static let nativeToolNames: Set<String> = [
        "desktop_action",
        "terminal_exec"
    ]

    func prepareMCPToolsForRun() async -> MCPPreparedTools {
        guard let mcpServerManager else {
            activeMCPPreparedTools = .empty
            return .empty
        }

        let prepared = await mcpServerManager.prepareForRun()
        activeMCPPreparedTools = prepared

        for status in prepared.serverStatuses {
            recordTrace(kind: .info, summarizeMCPStatus(status))
            for diagnostic in status.diagnostics {
                recordTrace(kind: .info, "MCP server \(status.serverID): \(truncate(diagnostic, limit: 300))")
            }
        }

        return prepared
    }

    func combinedToolDefinitions(mcpPreparedTools: MCPPreparedTools) -> [[String: Any]] {
        [
            desktopActionToolDefinition(),
            terminalExecToolDefinition()
        ] + mcpPreparedTools.tools.compactMap { definition in
            guard !Self.nativeToolNames.contains(definition.name.lowercased()) else {
                recordTrace(kind: .error, "Skipping MCP tool '\(definition.name)' because it collides with a native tool name.")
                return nil
            }
            return mcpToolDefinition(for: definition)
        }
    }

    func appendMCPRuntimeContext(to prompt: String, preparedTools: MCPPreparedTools) -> String {
        guard mcpServerManager != nil else { return prompt }

        var lines: [String] = [prompt]
        if !preparedTools.serverStatuses.isEmpty {
            lines.append("")
            lines.append("MCP_RUNTIME_STATUS:")
            for status in preparedTools.serverStatuses {
                lines.append("- \(status.serverID): \(summarizeMCPState(status.state))")
            }
        }
        if !preparedTools.tools.isEmpty {
            lines.append("")
            lines.append("AVAILABLE_MCP_TOOLS:")
            for tool in preparedTools.tools {
                lines.append("- \(tool.name): \(tool.description)")
            }
        }
        return lines.joined(separator: "\n")
    }

    func toolNamesForTrace() -> String {
        let names = ["desktop_action", "terminal_exec"] + activeMCPPreparedTools.tools.map(\.name)
        return names.joined(separator: ",")
    }

    func isMCPToolName(_ name: String) -> Bool {
        activeMCPPreparedTools.tools.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func summarizeMCPFunctionCallIfAvailable(_ functionCall: ParsedFunctionCall) -> String? {
        guard let definition = activeMCPPreparedTools.tools.first(where: {
            $0.name.caseInsensitiveCompare(functionCall.name) == .orderedSame
        }) else {
            return nil
        }

        guard let value = try? MCPValue.decodeJSON(from: functionCall.arguments) else {
            return "\(definition.name)(invalid_arguments)"
        }

        if let object = value.objectValue {
            let keys = object.keys.sorted()
            let summary = keys.prefix(4).map { key in
                let valuePreview = summarizeMCPValue(object[key])
                return "\(key)=\(valuePreview)"
            }.joined(separator: ", ")
            let suffix = keys.count > 4 ? ", ..." : ""
            return "\(definition.name)(\(summary)\(suffix))"
        }

        return "\(definition.name)(args=\(summarizeMCPValue(value)))"
    }

    func executeMCPFunctionCallIfAvailable(_ functionCall: ParsedFunctionCall) async -> ToolExecutionResult? {
        guard let mcpServerManager, isMCPToolName(functionCall.name) else {
            return nil
        }

        let arguments: MCPValue?
        do {
            arguments = try MCPValue.decodeJSON(from: functionCall.arguments)
        } catch {
            return ToolExecutionResult(
                callID: functionCall.callID,
                output: makeToolOutput(
                    ok: false,
                    message: "MCP tool input was invalid JSON.",
                    error: "invalid_input"
                ),
                isError: true,
                stepDescription: nil,
                generatedQuestions: ["MCP tool input from the model was invalid. What should I do?"]
            )
        }

        do {
            let result = try await mcpServerManager.callTool(named: functionCall.name, arguments: arguments)
            let output = (try? result.value.jsonString()) ?? String(describing: result.value.foundationObject())
            return ToolExecutionResult(
                callID: functionCall.callID,
                output: output,
                isError: result.isError,
                stepDescription: "Call MCP tool '\(functionCall.name)'",
                generatedQuestions: result.isError ? ["MCP tool '\(functionCall.name)' reported an error. What should I try next?"] : []
            )
        } catch {
            return ToolExecutionResult(
                callID: functionCall.callID,
                output: makeToolOutput(
                    ok: false,
                    message: "MCP tool '\(functionCall.name)' failed: \(error.localizedDescription)",
                    error: "mcp_execution_failed"
                ),
                isError: true,
                stepDescription: nil,
                generatedQuestions: ["MCP tool '\(functionCall.name)' failed. What should I do instead?"]
            )
        }
    }

    private func mcpToolDefinition(for definition: MCPToolDefinition) -> [String: Any] {
        let parameters = definition.inputSchema.foundationObject()
        let parameterObject = parameters as? [String: Any] ?? [
            "type": "object",
            "properties": [:],
            "additionalProperties": true
        ]

        return [
            "type": "function",
            "name": definition.name,
            "description": definition.description,
            "parameters": parameterObject
        ]
    }

    private func summarizeMCPStatus(_ status: MCPServerStatus) -> String {
        "MCP server \(status.serverID) (\(status.displayName)): \(summarizeMCPState(status.state))."
    }

    private func summarizeMCPState(_ state: MCPServerConnectionState) -> String {
        switch state {
        case .notStarted:
            return "not started"
        case .starting:
            return "starting"
        case .connected:
            return "connected"
        case .failed(let message):
            return "failed (\(truncate(message, limit: 200)))"
        case .disconnected(let message):
            return "disconnected (\(truncate(message, limit: 200)))"
        }
    }

    private func summarizeMCPValue(_ value: MCPValue?) -> String {
        guard let value else { return "null" }
        switch value {
        case .string(let text):
            return "\"\(truncate(text, limit: 60))\""
        case .number(let number):
            return String(number)
        case .bool(let flag):
            return flag ? "true" : "false"
        case .object(let object):
            return "{\(object.keys.sorted().prefix(4).joined(separator: ","))\(object.count > 4 ? ",..." : "")}"
        case .array(let array):
            return "[count=\(array.count)]"
        case .null:
            return "null"
        }
    }
}
