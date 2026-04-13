import Foundation

protocol MCPServerManaging: AnyObject, Sendable {
    func prepareForRun() async -> MCPPreparedTools
    func callTool(named toolName: String, arguments: MCPValue?) async throws -> MCPToolResult
}
