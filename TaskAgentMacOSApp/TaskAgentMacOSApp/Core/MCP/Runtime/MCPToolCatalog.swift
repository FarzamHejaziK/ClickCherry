import Foundation

nonisolated struct MCPToolCatalog: Equatable, Sendable {
    let definitions: [MCPToolDefinition]
    private let definitionsByName: [String: MCPToolDefinition]

    init() {
        self.definitions = []
        self.definitionsByName = [:]
    }

    init(definitions: [MCPToolDefinition]) throws {
        var byName: [String: MCPToolDefinition] = [:]
        for definition in definitions {
            if byName[definition.name] != nil {
                throw MCPRuntimeError.toolNameCollision(definition.name)
            }
            byName[definition.name] = definition
        }
        self.definitions = definitions
        self.definitionsByName = byName
    }

    func definition(named name: String) -> MCPToolDefinition? {
        definitionsByName[name]
    }
}
