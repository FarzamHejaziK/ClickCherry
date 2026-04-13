import Foundation

actor MCPServerManager: MCPServerManaging {
    private let definitionsByID: [String: MCPServerDefinition]
    private var sessionsByID: [String: MCPServerSession] = [:]
    private var toolCatalog = MCPToolCatalog()

    init(serverDefinitions: [MCPServerDefinition]) {
        self.definitionsByID = Dictionary(uniqueKeysWithValues: serverDefinitions.map { ($0.id, $0) })
    }

    func listApprovedServers() -> [MCPServerDefinition] {
        definitionsByID.values.sorted { $0.id < $1.id }
    }

    func ensureStarted(serverID: String) async throws {
        guard let definition = definitionsByID[serverID] else {
            throw MCPRuntimeError.serverNotApproved(serverID)
        }
        let session = session(for: definition)
        try await session.ensureStarted()
    }

    func listTools(serverID: String) async throws -> [MCPToolDefinition] {
        guard let definition = definitionsByID[serverID] else {
            throw MCPRuntimeError.serverNotApproved(serverID)
        }
        let session = session(for: definition)
        return try await session.listTools()
    }

    func prepareForRun() async -> MCPPreparedTools {
        let approved = listApprovedServers().filter(\.enabledByDefault)
        guard !approved.isEmpty else {
            toolCatalog = MCPToolCatalog()
            return .empty
        }

        var allTools: [MCPToolDefinition] = []
        var statuses: [MCPServerStatus] = []

        for definition in approved {
            let session = session(for: definition)
            do {
                let tools = try await session.listTools()
                allTools.append(contentsOf: tools)
            } catch {
                // status will capture the failure below
            }
            statuses.append(await session.currentStatus())
        }

        if let catalog = try? MCPToolCatalog(definitions: allTools) {
            toolCatalog = catalog
            return MCPPreparedTools(tools: catalog.definitions, serverStatuses: statuses)
        }

        toolCatalog = MCPToolCatalog()
        return MCPPreparedTools(tools: [], serverStatuses: statuses)
    }

    func callTool(serverID: String, toolName: String, arguments: MCPValue?) async throws -> MCPToolResult {
        guard let definition = definitionsByID[serverID] else {
            throw MCPRuntimeError.serverNotApproved(serverID)
        }
        let session = session(for: definition)
        return try await session.callTool(name: toolName, arguments: arguments)
    }

    func callTool(named toolName: String, arguments: MCPValue?) async throws -> MCPToolResult {
        guard let definition = toolCatalog.definition(named: toolName) else {
            throw MCPRuntimeError.toolNotFound(toolName)
        }
        return try await callTool(serverID: definition.serverID, toolName: definition.name, arguments: arguments)
    }

    private func session(for definition: MCPServerDefinition) -> MCPServerSession {
        if let existing = sessionsByID[definition.id] {
            return existing
        }
        let created = MCPServerSession(definition: definition)
        sessionsByID[definition.id] = created
        return created
    }
}
