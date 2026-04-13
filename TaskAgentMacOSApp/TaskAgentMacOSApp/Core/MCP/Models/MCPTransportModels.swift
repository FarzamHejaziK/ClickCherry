import Foundation

nonisolated enum MCPValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: MCPValue])
    case array([MCPValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: MCPValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([MCPValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported MCP JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        default:
            return nil
        }
    }

    var numberValue: Double? {
        switch self {
        case .number(let value):
            return value
        case .string(let value):
            return Double(value)
        default:
            return nil
        }
    }

    var intValue: Int? {
        guard let numberValue else { return nil }
        return Int(numberValue.rounded())
    }

    var boolValue: Bool? {
        if case .bool(let value) = self {
            return value
        }
        return nil
    }

    var objectValue: [String: MCPValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }

    var arrayValue: [MCPValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }

    func foundationObject() -> Any {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .object(let value):
            return value.mapValues { $0.foundationObject() }
        case .array(let value):
            return value.map { $0.foundationObject() }
        case .null:
            return NSNull()
        }
    }

    func encodedData() throws -> Data {
        try JSONEncoder().encode(self)
    }

    func jsonString() throws -> String {
        let data = try encodedData()
        guard let string = String(data: data, encoding: .utf8) else {
            throw MCPRuntimeError.invalidResponse("Failed to encode MCP value as UTF-8 text.")
        }
        return string
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: encodedData())
    }

    static func decodeJSON(from text: String) throws -> MCPValue {
        try JSONDecoder().decode(MCPValue.self, from: Data(text.utf8))
    }
}

nonisolated struct MCPClientInfo: Codable, Equatable, Sendable {
    var name: String
    var version: String
}

nonisolated struct MCPInitializeParams: Codable, Equatable, Sendable {
    var protocolVersion: String
    var capabilities: [String: MCPValue]
    var clientInfo: MCPClientInfo
}

nonisolated struct MCPServerInfo: Codable, Equatable, Sendable {
    var name: String
    var version: String
}

nonisolated struct MCPInitializeResult: Codable, Equatable, Sendable {
    var protocolVersion: String
    var capabilities: [String: MCPValue]
    var serverInfo: MCPServerInfo
}

nonisolated struct MCPRemoteToolPayload: Codable, Equatable, Sendable {
    var name: String
    var description: String?
    var inputSchema: MCPValue?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema
    }
}

nonisolated struct MCPListToolsResult: Codable, Equatable, Sendable {
    var tools: [MCPRemoteToolPayload]
}

nonisolated struct MCPCallToolParams: Codable, Equatable, Sendable {
    var name: String
    var arguments: MCPValue?
}

nonisolated struct MCPJSONRPCRequestEnvelope: Encodable, Equatable, Sendable {
    var jsonrpc: String = "2.0"
    var id: Int
    var method: String
    var params: MCPValue?
}

nonisolated struct MCPJSONRPCNotificationEnvelope: Encodable, Equatable, Sendable {
    var jsonrpc: String = "2.0"
    var method: String
    var params: MCPValue?
}

nonisolated struct MCPJSONRPCResponseEnvelope: Decodable, Equatable, Sendable {
    var jsonrpc: String
    var id: MCPValue?
    var result: MCPValue?
    var error: MCPJSONRPCError?
}

nonisolated struct MCPJSONRPCError: Codable, Equatable, Sendable, Error {
    var code: Int
    var message: String
    var data: MCPValue?
}

nonisolated enum MCPRuntimeError: LocalizedError, Equatable, Sendable {
    case executableNotFound(String)
    case processNotStarted(String)
    case requestTimedOut(method: String, seconds: Double)
    case invalidResponse(String)
    case serverDisconnected(String)
    case serverFailedToStart(String)
    case serverNotApproved(String)
    case toolNotFound(String)
    case toolNameCollision(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let executable):
            return "MCP executable '\(executable)' was not found."
        case .processNotStarted(let serverID):
            return "MCP server '\(serverID)' is not running."
        case .requestTimedOut(let method, let seconds):
            return "MCP request '\(method)' timed out after \(String(format: "%.1f", seconds)) seconds."
        case .invalidResponse(let message):
            return "MCP response was invalid: \(message)"
        case .serverDisconnected(let message):
            return "MCP server disconnected: \(message)"
        case .serverFailedToStart(let message):
            return "MCP server failed to start: \(message)"
        case .serverNotApproved(let serverID):
            return "MCP server '\(serverID)' is not approved."
        case .toolNotFound(let toolName):
            return "MCP tool '\(toolName)' was not found."
        case .toolNameCollision(let toolName):
            return "MCP tool name collision for '\(toolName)'."
        }
    }
}
