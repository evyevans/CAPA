import Foundation

public struct WorkspaceIdentity: Codable, Sendable {
    public let device_id: String
    public let workspace_id: String
    public let name: String
    public let reply_mode: String
    public let preferred_device_id: String?
}

public struct LinkedDevice: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let platform: String
    public let available: Int
    public let revoked: Int
}

public struct DeviceInvitation: Codable, Sendable {
    public let code: String
    public let expires_in: Int
}

public struct AgentConnection: Codable, Identifiable, Sendable {
    public let name: String
    public let label: String?
    public let description: String?
    public let enabled: Bool?
    public let configured: Bool?
    public let tools: [String]?
    public var id: String { name }
    public var status: String {
        if enabled == false { return "Disabled in Hermes" }
        if configured == false { return "Needs setup in Hermes" }
        if configured == true && enabled == true { return "Available to Hermes" }
        return "Advertised by Hermes · status unknown"
    }
}

public struct AgentSkill: Codable, Identifiable, Sendable {
    public let name: String
    public let description: String?
    public var id: String { name }
}

public struct ConnectionInventory: Codable, Sendable {
    public let discovery_available: Bool
    public let toolsets: [AgentConnection]
    public let skills: [AgentSkill]
    public let message: String
}

public extension BridgeClient {
    func identity() async throws -> WorkspaceIdentity { try await call("v1/me") }
    func linkedDevices() async throws -> [LinkedDevice] { try await call("v1/devices") }
    func invite() async throws -> DeviceInvitation { try await call("v1/devices/link", method: "POST") }
    func connections() async throws -> ConnectionInventory { try await call("v1/connections") }
    func preferences(mode: String, deviceID: String) async throws -> WorkspaceIdentity {
        try await call("v1/workspace", method: "PUT", body: ["reply_mode": mode, "preferred_device_id": deviceID])
    }
    func revokeDevice(_ id: String) async throws { _ = try await request("v1/devices/\(id)", method: "DELETE") }
}
