import Foundation

public enum BridgeError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

public struct PairReply: Decodable { public let device_id: String; public let token: String }
public struct BridgeCapabilities: Decodable { public let push_configured: Bool; public let host_speech: Bool }

public struct BridgeClient: Sendable {
    public let credential: Credential
    public init(credential: Credential) { self.credential = credential }
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.urlCache = nil
        config.httpCookieStorage = nil
        return URLSession(configuration: config)
    }()

    public static func validatedBaseURL(_ value: String, platform: String) throws -> URL {
        guard let base = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = base.host, base.user == nil, base.password == nil,
              base.query == nil, base.fragment == nil else {
            throw BridgeError.message("Enter a bridge address without credentials or a query.")
        }
        let localMac = platform == "macos" && base.scheme == "http" &&
            ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host.lowercased())
        guard base.scheme == "https" || localMac else {
            throw BridgeError.message("Use trusted HTTPS, or http://127.0.0.1:8787 for a bridge on this Mac.")
        }
        return base
    }

    public static func pair(url: String, code: String, name: String = "CAPA iPhone", platform: String = "ios") async throws -> Credential {
        let base = try validatedBaseURL(url, platform: platform)
        let temporary = BridgeClient(credential: Credential(baseURL: base, token: "", deviceID: ""))
        let result: PairReply = try await temporary.call("v1/pair", method: "POST", body: [
            "code": code.trimmingCharacters(in: .whitespacesAndNewlines), "name": name, "platform": platform])
        return Credential(baseURL: base, token: result.token, deviceID: result.device_id)
    }

    public func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        var request = URLRequest(url: credential.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        if path.hasSuffix("/audio") { request.timeoutInterval = 95 }
        if !credential.token.isEmpty { request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BridgeError.message("No response from your bridge.") }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw BridgeError.message(detail ?? "Bridge request failed (\(http.statusCode)). Refresh before retrying.")
        }
        return data
    }

    public func call<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        try JSONDecoder().decode(T.self, from: await request(path, method: method, body: body))
    }

    public func submit(_ memo: PendingMemo) async throws -> AgentTask {
        try await call("v1/tasks", method: "POST", body: ["request_id": memo.requestID, "text": memo.text])
    }
    public func tasks() async throws -> [AgentTask] { try await call("v1/tasks") }
    public func events() async throws -> [AgentEvent] { try await call("v1/events") }
    public func event(_ id: String) async throws -> AgentEvent { try await call("v1/events/\(id)") }
    public func acknowledge(_ id: String, token: String? = nil) async throws {
        _ = try await request("v1/events/\(id)/ack", method: "POST", body: token.map { ["token": $0] })
    }
    public func claim(_ id: String, token: String, manual: Bool) async throws {
        _ = try await request("v1/events/\(id)/claim", method: "POST", body: ["token": token, "manual": manual])
    }
    public func device(_ body: [String: Any]) async throws { _ = try await request("v1/device", method: "PUT", body: body) }
    public func revoke() async throws { _ = try await request("v1/device", method: "DELETE") }
    public func stop(_ id: String) async throws { _ = try await request("v1/tasks/\(id)/stop", method: "POST") }
    public func control(taskID: String, control: AgentControl, answer: String? = nil, choice: String? = nil) async throws {
        guard let generation = control.executionGeneration, control.id != "unsupported" else {
            throw BridgeError.message("Hermes did not provide a supported control identity.")
        }
        var body: [String: Any] = ["request_id": control.id, "execution_generation": generation]
        if let answer { body["answer"] = answer }
        if let choice { body["choice"] = choice }
        _ = try await request("v1/tasks/\(taskID)/control", method: "POST", body: body)
    }

    public func transcribe(_ url: URL) async throws -> String {
        var request = URLRequest(url: credential.baseURL.appendingPathComponent("v1/transcribe"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Data(contentsOf: url)
        request.timeoutInterval = 120
        let (data, response) = try await Self.session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let result = try JSONSerialization.jsonObject(with: data) as? [String: String],
              let text = result["text"] else { throw BridgeError.message("Host transcription failed. Your memo is saved for retry.") }
        return text
    }

    public func audio(_ id: String) async throws -> Data { try await request("v1/events/\(id)/audio", method: "POST") }
}
