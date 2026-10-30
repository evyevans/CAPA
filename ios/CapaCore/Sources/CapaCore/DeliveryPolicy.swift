import Foundation

/// Eligibility and receipt state are independent of the agent's execution state.
public struct DeliveryPolicy: Codable, Sendable {
    public var available: Bool
    public private(set) var acknowledged: Set<String>
    public private(set) var playing: String?

    public init(available: Bool, acknowledged: Set<String> = []) {
        self.available = available
        self.acknowledged = acknowledged
    }

    public mutating func begin(_ eventID: String) -> Bool {
        guard available, playing == nil, !acknowledged.contains(eventID) else { return false }
        playing = eventID
        return true
    }

    public mutating func finished(_ eventID: String) {
        acknowledged.insert(eventID)
        if playing == eventID { playing = nil }
    }

    public mutating func interrupted() { playing = nil }
}

public struct PendingMemo: Codable, Sendable {
    public enum Phase: String, Codable, Sendable { case draft, sending, unconfirmed, accepted }
    public let requestID: String
    public var text: String
    public private(set) var phase: Phase = .draft
    public var canDiscard: Bool { phase == .draft }

    public init(text: String) {
        self.text = text
        requestID = UUID().uuidString
    }

    public mutating func markSending() { phase = .sending }
    public mutating func markUnconfirmed() { phase = .unconfirmed }
    public mutating func accept(runID: String?) {
        phase = (runID?.isEmpty == false) ? .accepted : .unconfirmed
    }
}
