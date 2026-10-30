import Foundation

public struct AgentControl: Codable, Identifiable, Sendable {
    public var kind: String?
    public var type: String?
    public var promptID: String?
    public var requestID: String?
    public var executionGeneration: Int?
    public var question: String?
    public var prompt: String?
    public var description: String?
    public var command: String?
    public var edit: JSONValue?
    public var choices: [String]?
    public var id: String { promptID ?? requestID ?? "unsupported" }
    public var isClarification: Bool { ["clarify", "clarification"].contains(kind ?? type ?? "") }
    public var label: String {
        [question, prompt, description, command].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: "\n\n").nilIfEmpty ?? "Hermes needs your review."
    }
    public var editDescription: String? {
        guard let edit, let data = try? JSONEncoder.pretty.encode(edit) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    public var canApproveOnce: Bool {
        choices?.contains("once") == true && executionGeneration != nil && id != "unsupported" &&
            ((command?.isEmpty == false) || edit != nil)
    }

    enum CodingKeys: String, CodingKey {
        case kind, type, question, prompt, description, command, edit, choices
        case promptID = "prompt_id", requestID = "request_id", executionGeneration = "execution_generation"
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder
    }
}

public enum JSONValue: Codable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
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

public struct ClarificationReply: Codable, Sendable {
    public let taskID: String
    public let control: AgentControl
    public init?(taskID: String, control: AgentControl) {
        guard control.isClarification, control.executionGeneration != nil, control.id != "unsupported" else { return nil }
        self.taskID = taskID; self.control = control
    }
}

public struct AgentTask: Codable, Identifiable, Sendable {
    public let id: String
    public let text: String
    public let status: String
    public let runID: String?
    public let output: String
    public let controls: [AgentControl]
    public let createdAt: Double
    public var terminal: Bool { ["completed", "failed", "cancelled", "interrupted", "unknown"].contains(status) }
    enum CodingKeys: String, CodingKey {
        case id, text, status, output, controls
        case runID = "run_id", createdAt = "created_at"
    }
}

public struct AgentEvent: Codable, Identifiable, Sendable {
    public let id: String
    public let taskID: String
    public let kind: String
    public let text: String
    public let spokenText: String
    public let acknowledged: Int
    public let deliveryDeviceID: String?
    public var requiresReview: Bool { kind == "approval" || kind == "clarification" }
    public var announcement: String {
        kind == "approval" ? "Hermes needs your approval. Open CAPA to review the action." : spokenText
    }
    enum CodingKeys: String, CodingKey {
        case id, kind, text, acknowledged
        case taskID = "task_id", spokenText = "spoken_text"
        case deliveryDeviceID = "delivery_device_id"
    }
}
