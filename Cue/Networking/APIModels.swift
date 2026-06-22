import Foundation

// MARK: - JSONValue

/// A minimal, `Codable` JSON value. Used for two things:
/// 1. Decoding the arbitrary `input` payload of a `tool_use` block.
/// 2. Building tool `input_schema` definitions in a type-safe, literal-friendly
///    way (see `ToolDefinitions`).
enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
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
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

extension JSONValue {
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }
    /// Convenience object subscript; returns `nil` if the value is not an object.
    subscript(_ key: String) -> JSONValue? { objectValue?[key] }
}

// Literal conformances make building JSON Schema definitions read naturally.
extension JSONValue: ExpressibleByStringLiteral {
    init(stringLiteral value: String) { self = .string(value) }
}
extension JSONValue: ExpressibleByBooleanLiteral {
    init(booleanLiteral value: Bool) { self = .bool(value) }
}
extension JSONValue: ExpressibleByIntegerLiteral {
    init(integerLiteral value: Int) { self = .number(Double(value)) }
}
extension JSONValue: ExpressibleByFloatLiteral {
    init(floatLiteral value: Double) { self = .number(value) }
}
extension JSONValue: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}
extension JSONValue: ExpressibleByDictionaryLiteral {
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

// MARK: - Content blocks

/// A single content block in a message. The Messages API interleaves `text`,
/// `tool_use` (assistant → app), and `tool_result` (app → model) blocks.
enum ContentBlock: Codable, Equatable, Sendable {
    case text(String)
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(toolUseID: String, content: String, isError: Bool)
    /// Any block type we don't model (e.g. `thinking`); decoded so we never fail,
    /// and filtered out before echoing assistant turns back to the API.
    case unknown(type: String)

    private enum CodingKeys: String, CodingKey {
        case type, text, id, name, input
        case toolUseID = "tool_use_id"
        case content
        case isError = "is_error"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "tool_use":
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let input = try container.decodeIfPresent(JSONValue.self, forKey: .input) ?? .object([:])
            self = .toolUse(id: id, name: name, input: input)
        case "tool_result":
            let toolUseID = try container.decode(String.self, forKey: .toolUseID)
            let content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
            let isError = try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false
            self = .toolResult(toolUseID: toolUseID, content: content, isError: isError)
        default:
            self = .unknown(type: type)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .toolUse(let id, let name, let input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case .toolResult(let toolUseID, let content, let isError):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseID, forKey: .toolUseID)
            try container.encode(content, forKey: .content)
            try container.encode(isError, forKey: .isError)
        case .unknown(let type):
            try container.encode(type, forKey: .type)
        }
    }
}

extension ContentBlock {
    /// `false` for `.unknown`; used to filter blocks we can't safely re-encode.
    var isKnown: Bool {
        if case .unknown = self { return false }
        return true
    }
    var textValue: String? {
        if case .text(let text) = self { return text }
        return nil
    }
    var toolUse: (id: String, name: String, input: JSONValue)? {
        if case .toolUse(let id, let name, let input) = self { return (id, name, input) }
        return nil
    }
}

extension Array where Element == ContentBlock {
    /// First `tool_use` block, if any.
    var firstToolUse: (id: String, name: String, input: JSONValue)? {
        for block in self {
            if let tool = block.toolUse { return tool }
        }
        return nil
    }
    /// All `tool_use` blocks, in order. The model may propose several in one turn
    /// (e.g. "add X and Y"); each needs its own `tool_result` in reply.
    var allToolUses: [(id: String, name: String, input: JSONValue)] {
        compactMap { $0.toolUse }
    }
    /// All text blocks joined, trimmed — the assistant's prose for this turn.
    var joinedText: String {
        compactMap { $0.textValue }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Messages

/// A wire-format message in the running conversation history.
struct APIMessage: Codable, Equatable, Sendable {
    let role: String   // "user" | "assistant"
    let content: [ContentBlock]
}

// MARK: - Tool definitions

/// A function-calling tool definition sent in the request `tools` array.
struct ToolDefinition: Encodable, Sendable {
    let name: String
    let description: String
    let inputSchema: JSONValue

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

// MARK: - Request / Response

/// The Messages API request body.
struct MessagesRequest: Encodable, Sendable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [APIMessage]
    let tools: [ToolDefinition]

    enum CodingKeys: String, CodingKey {
        case model, system, messages, tools
        case maxTokens = "max_tokens"
    }
}

/// The Messages API response body (only the fields Cue needs).
struct MessagesResponse: Decodable, Sendable {
    let id: String?
    let role: String?
    let model: String?
    let stopReason: String?
    let content: [ContentBlock]

    enum CodingKeys: String, CodingKey {
        case id, role, model, content
        case stopReason = "stop_reason"
    }

    init(id: String?, role: String?, model: String?, stopReason: String?, content: [ContentBlock]) {
        self.id = id
        self.role = role
        self.model = model
        self.stopReason = stopReason
        self.content = content
    }
}

/// The Messages API error envelope, used to extract a readable message on failure.
struct APIErrorResponse: Decodable, Sendable {
    struct Detail: Decodable, Sendable {
        let type: String?
        let message: String?
    }
    let type: String?
    let error: Detail?
}
