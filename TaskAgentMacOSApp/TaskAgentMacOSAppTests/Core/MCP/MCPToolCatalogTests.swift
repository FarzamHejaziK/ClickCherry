import Testing
@testable import TaskAgentMacOSApp

struct MCPToolCatalogTests {
    @Test
    func rejectsDuplicateToolNamesAcrossServers() throws {
        let definitions = [
            MCPToolDefinition(serverID: "a", name: "browser_snapshot", description: "", inputSchema: .object([:])),
            MCPToolDefinition(serverID: "b", name: "browser_snapshot", description: "", inputSchema: .object([:]))
        ]

        #expect(throws: MCPRuntimeError.toolNameCollision("browser_snapshot")) {
            _ = try MCPToolCatalog(definitions: definitions)
        }
    }
}
