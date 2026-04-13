import Foundation

nonisolated struct MCPToolDefinition: Equatable, Sendable {
    var serverID: String
    var name: String
    var description: String
    var inputSchema: MCPValue
}

nonisolated struct MCPToolCall: Equatable, Sendable {
    var serverID: String
    var toolName: String
    var arguments: MCPValue?
}

nonisolated struct MCPToolResult: Equatable, Sendable {
    var serverID: String
    var toolName: String
    var value: MCPValue
    var isError: Bool
}
