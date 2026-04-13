import Foundation
import Testing
@testable import TaskAgentMacOSApp

struct MCPJSONRPCClientTests {
    @Test
    func initializesListsToolsAndCallsToolAgainstFakeServer() async throws {
        let scriptURL = try MCPTestServerFixture.makeServerScript()
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let definition = MCPServerDefinition(
            id: "fake_mcp",
            displayName: "Fake MCP",
            command: "/usr/bin/python3",
            args: [scriptURL.path],
            startupTimeout: 5
        )

        let process = MCPServerProcess(definition: definition)
        let transport = try process.start()
        defer { process.stop() }

        let client = MCPJSONRPCClient(transport: transport, requestTimeout: 5)
        await client.installTransportHandlers()

        let initializeValue = try await client.request(
            method: "initialize",
            params: .object([
                "protocolVersion": .string("2025-03-26"),
                "capabilities": .object([:]),
                "clientInfo": .object([
                    "name": .string("ClickCherry Tests"),
                    "version": .string("0.1")
                ])
            ])
        )
        let initialize = try initializeValue.decode(MCPInitializeResult.self)
        #expect(initialize.serverInfo.name == "Fake MCP Server")

        try await client.notify(method: "notifications/initialized", params: .object([:]))

        let listToolsValue = try await client.request(method: "tools/list", params: .object([:]))
        let tools = try listToolsValue.decode(MCPListToolsResult.self)
        #expect(tools.tools.map(\.name) == ["browser_snapshot"])

        let callValue = try await client.request(
            method: "tools/call",
            params: .object([
                "name": .string("browser_snapshot"),
                "arguments": .object(["kind": .string("dom")])
            ])
        )
        #expect(callValue.objectValue?["content"]?.arrayValue?.isEmpty == false)
    }
}
