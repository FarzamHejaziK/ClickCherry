import Foundation

nonisolated struct MCPServerDefinition: Equatable, Sendable {
    var id: String
    var displayName: String
    var command: String
    var args: [String]
    var environment: [String: String]
    var startupTimeout: TimeInterval
    var enabledByDefault: Bool

    init(
        id: String,
        displayName: String,
        command: String,
        args: [String],
        environment: [String: String] = [:],
        startupTimeout: TimeInterval = 15,
        enabledByDefault: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.command = command
        self.args = args
        self.environment = environment
        self.startupTimeout = startupTimeout
        self.enabledByDefault = enabledByDefault
    }
}

nonisolated enum MCPServerConnectionState: Equatable, Sendable {
    case notStarted
    case starting
    case connected
    case failed(String)
    case disconnected(String)
}

nonisolated struct MCPServerStatus: Equatable, Sendable {
    var serverID: String
    var displayName: String
    var state: MCPServerConnectionState
    var diagnostics: [String] = []
}

nonisolated struct MCPPreparedTools: Equatable, Sendable {
    var tools: [MCPToolDefinition]
    var serverStatuses: [MCPServerStatus]

    static let empty = MCPPreparedTools(tools: [], serverStatuses: [])
}
