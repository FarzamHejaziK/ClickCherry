import Foundation
import Testing
@testable import TaskAgentMacOSApp

struct MCPServerManagerTests {
    @Test
    func prepareForRunLoadsApprovedToolCatalog() async throws {
        let scriptURL = try MCPTestServerFixture.makeServerScript()
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let definition = MCPServerDefinition(
            id: "fake_mcp",
            displayName: "Fake MCP",
            command: "/usr/bin/python3",
            args: [scriptURL.path],
            startupTimeout: 5
        )

        let manager = MCPServerManager(serverDefinitions: [definition])
        let prepared = await manager.prepareForRun()

        #expect(prepared.tools.map(\.name) == ["browser_snapshot"])
        #expect(prepared.serverStatuses.count == 1)
        let status = try #require(prepared.serverStatuses.first)
        #expect(status.serverID == "fake_mcp")
        #expect(status.state == .connected)
        #expect(status.diagnostics.contains("Sending MCP initialize request."))
        #expect(status.diagnostics.contains("Received MCP initialize response."))
        #expect(status.diagnostics.contains("Requesting MCP tools/list."))
        #expect(status.diagnostics.contains("Received MCP tools/list response."))
    }

    @Test
    func callToolRoutesThroughPreparedCatalog() async throws {
        let scriptURL = try MCPTestServerFixture.makeServerScript()
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let definition = MCPServerDefinition(
            id: "fake_mcp",
            displayName: "Fake MCP",
            command: "/usr/bin/python3",
            args: [scriptURL.path],
            startupTimeout: 5
        )

        let manager = MCPServerManager(serverDefinitions: [definition])
        _ = await manager.prepareForRun()
        let result = try await manager.callTool(named: "browser_snapshot", arguments: .object([:]))

        #expect(result.serverID == "fake_mcp")
        #expect(result.toolName == "browser_snapshot")
        #expect(result.isError == false)
    }

    @Test
    func prepareForRunCapturesStartupDiagnosticsWhenServerExitsEarly() async throws {
        let definition = MCPServerDefinition(
            id: "failing_mcp",
            displayName: "Failing MCP",
            command: "/usr/bin/python3",
            args: ["-c", "import sys; sys.stderr.write('bridge boom\\n'); sys.stderr.flush(); sys.exit(2)"],
            startupTimeout: 1
        )

        let manager = MCPServerManager(serverDefinitions: [definition])
        let prepared = await manager.prepareForRun()

        #expect(prepared.tools.isEmpty)
        #expect(prepared.serverStatuses.count == 1)

        let status = try #require(prepared.serverStatuses.first)
        #expect(status.serverID == "failing_mcp")

        guard case .failed(let message) = status.state else {
            Issue.record("Expected failing MCP server status, got \(status.state)")
            return
        }

        #expect(message.contains("initialize handshake"))
        #expect(status.diagnostics.contains(where: { $0.contains("Launch command: /usr/bin/python3") }))
        #expect(status.diagnostics.contains(where: { $0.contains("Resolved executable: /usr/bin/python3") }))
        #expect(status.diagnostics.contains(where: { $0.contains("bridge boom") }))
    }
}
