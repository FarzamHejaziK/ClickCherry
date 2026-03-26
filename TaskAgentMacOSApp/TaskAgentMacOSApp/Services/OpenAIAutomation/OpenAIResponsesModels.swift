import Foundation

struct OpenAIResponsesResponse: Decodable {
    var id: String?
    var output: [OpenAIResponseOutputItem]?
    var outputText: String?

    enum CodingKeys: String, CodingKey {
        case id
        case output
        case outputText = "output_text"
    }
}

struct OpenAIResponseOutputItem: Decodable {
    var type: String
    var id: String?
    var callID: String?
    var name: String?
    var arguments: OpenAIJSONValue?
    var content: [OpenAIResponseMessageContent]?
    var text: String?

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case callID = "call_id"
        case name
        case arguments
        case content
        case text
    }
}

struct OpenAIResponseMessageContent: Decodable {
    var type: String
    var text: String?
}

struct OpenAIErrorEnvelope: Decodable {
    struct Payload: Decodable {
        var message: String?
        var type: String?
        var code: String?
    }

    var error: Payload?
}

struct OpenAIToolLoopCompletionPayload: Decodable {
    var status: String
    var summary: String?
    var error: String?
    var questions: [String]?
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
