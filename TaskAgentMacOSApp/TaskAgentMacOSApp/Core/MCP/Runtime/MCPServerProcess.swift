import Foundation

nonisolated final class MCPServerProcess: @unchecked Sendable {
    let definition: MCPServerDefinition
    private(set) var transport: MCPStdioTransport?

    init(definition: MCPServerDefinition) {
        self.definition = definition
    }

    func start() throws -> MCPStdioTransport {
        let transport = MCPStdioTransport()
        try transport.start(definition: definition)
        self.transport = transport
        return transport
    }

    func restart() throws -> MCPStdioTransport {
        stop()
        return try start()
    }

    func stop() {
        transport?.stop()
        transport = nil
    }

    var resolvedExecutablePath: String? {
        transport?.resolvedExecutablePath
    }

    var launchCommandSummary: String {
        let pieces = [definition.command] + definition.args
        return pieces.map(Self.shellEscape).joined(separator: " ")
    }

    private static func shellEscape(_ value: String) -> String {
        guard !value.isEmpty else { return "\"\"" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./:@="))
        if value.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            return value
        }

        let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
