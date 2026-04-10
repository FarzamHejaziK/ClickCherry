import Foundation

enum OpenAIResponsesTransportMode: String, Codable {
    case http
    case webSocketPreferred = "websocket_preferred"
    case webSocketOnly = "websocket_only"
}

struct OpenAIResponsesTransportRequest {
    var model: String
    var input: [[String: Any]]
    var tools: [[String: Any]]
    var previousResponseId: String?
    var reasoningEffort: String?
    var reasoningSummary: String?
    var apiKey: String

    func responseCreateBody() -> [String: Any] {
        var requestBody: [String: Any] = [
            "model": model,
            "input": input,
            "tools": tools,
            "tool_choice": "auto",
            "truncation": "auto"
        ]
        if let previousResponseId, !previousResponseId.isEmpty {
            requestBody["previous_response_id"] = previousResponseId
        }
        if let reasoningEffort, !reasoningEffort.isEmpty {
            var reasoning: [String: Any] = ["effort": reasoningEffort]
            if let reasoningSummary, !reasoningSummary.isEmpty {
                reasoning["summary"] = reasoningSummary
            }
            requestBody["reasoning"] = reasoning
        }
        return requestBody
    }

    func encodedResponseCreateBody() throws -> Data {
        try JSONSerialization.data(withJSONObject: responseCreateBody())
    }

    func encodedWebSocketEvent() throws -> Data {
        var body = responseCreateBody()
        body["type"] = "response.create"
        return try JSONSerialization.data(withJSONObject: body)
    }
}

struct OpenAIResponsesResponse: Codable {
    var id: String?
    var output: [OpenAIResponseOutputItem]?
    var outputText: String?

    enum CodingKeys: String, CodingKey {
        case id
        case output
        case outputText = "output_text"
    }
}

struct OpenAIResponseOutputItem: Codable {
    var type: String
    var id: String?
    var callID: String?
    var name: String?
    var arguments: OpenAIJSONValue?
    var content: [OpenAIResponseMessageContent]?
    var summary: [OpenAIResponseMessageContent]?
    var text: String?

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case callID = "call_id"
        case name
        case arguments
        case content
        case summary
        case text
    }
}

struct OpenAIResponseMessageContent: Codable {
    var type: String
    var text: String?
}

struct OpenAIErrorEnvelope: Codable {
    struct Payload: Codable {
        var message: String?
        var type: String?
        var code: String?
    }

    var error: Payload?
}

struct OpenAIToolLoopCompletionPayload: Codable {
    var status: String
    var summary: String?
    var verificationStatus: String?
    var evidence: String?
    var error: String?
    var questions: [String]?
    var debugVisualObservation: String?
    var debugMouseLocation: String?

    enum CodingKeys: String, CodingKey {
        case status
        case summary
        case verificationStatus = "verification_status"
        case evidence
        case error
        case questions
        case debugVisualObservation = "debug_visual_observation"
        case debugMouseLocation = "debug_mouse_location"
    }
}

struct OpenAIResponsesWebSocketEvent: Decodable {
    var type: String
    var status: Int?
    var requestID: String?
    var error: OpenAIErrorEnvelope.Payload?
    var response: OpenAIResponsesResponse?
    var item: OpenAIResponseOutputItem?
    var outputIndex: Int?
    var itemID: String?
    var delta: String?
    var arguments: String?
    var text: String?

    enum CodingKeys: String, CodingKey {
        case type
        case status
        case requestID = "request_id"
        case error
        case response
        case item
        case outputIndex = "output_index"
        case itemID = "item_id"
        case delta
        case arguments
        case text
    }
}

enum OpenAIJSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: OpenAIJSONValue])
    case array([OpenAIJSONValue])
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
        } else if let value = try? container.decode([String: OpenAIJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([OpenAIJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
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
        case .number(let value):
            return String(value)
        default:
            return nil
        }
    }

    var doubleValue: Double? {
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
        guard let double = doubleValue else {
            return nil
        }
        return Int(double.rounded())
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .string(let value):
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                return nil
            }
        case .number(let value):
            return value != 0
        default:
            return nil
        }
    }

    var objectValue: [String: OpenAIJSONValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }

    var arrayValue: [OpenAIJSONValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }

    func jsonString(using encoder: JSONEncoder) -> String? {
        if case .string(let raw) = self {
            return raw
        }
        guard let data = try? encoder.encode(self),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }
}
