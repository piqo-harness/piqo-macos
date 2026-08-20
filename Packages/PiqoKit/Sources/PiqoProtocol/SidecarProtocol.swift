import Foundation

public enum ProtocolError: LocalizedError, Sendable, Equatable {
    case malformedStartup
    case unsupportedProtocol(Int)
    case unsupportedAPI(String)
    case invalidOrigin(String)
    case pidMismatch(expected: Int32, received: Int)
    case malformedEvent(String)

    public var errorDescription: String? {
        switch self {
        case .malformedStartup: "The sidecar returned an incompatible startup message."
        case .unsupportedProtocol(let version): "Unsupported sidecar protocol version \(version)."
        case .unsupportedAPI(let version): "Unsupported sidecar API version \(version)."
        case .invalidOrigin(let value): "The sidecar announced an unsafe origin: \(value)."
        case .pidMismatch: "The ready message did not belong to the launched sidecar."
        case .malformedEvent(let message): message
        }
    }
}

public struct SidecarReady: Sendable, Codable, Equatable {
    public let type: String
    public let protocolVersion: Int
    public let serverVersion: String
    public let apiVersion: String
    public let pid: Int
    public let baseURL: String
    public let token: String

    enum CodingKeys: String, CodingKey {
        case type
        case protocolVersion = "protocol_version"
        case serverVersion = "server_version"
        case apiVersion = "api_version"
        case pid
        case baseURL = "base_url"
        case token
    }

    public func validated(expectedPID: Int32?) throws -> ValidatedSidecar {
        guard type == "ready", protocolVersion == 1 else {
            throw protocolVersion == 1 ? ProtocolError.malformedStartup : ProtocolError.unsupportedProtocol(protocolVersion)
        }
        guard apiVersion == "v1" else { throw ProtocolError.unsupportedAPI(apiVersion) }
        guard pid > 0, token.count == 43, token.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
            throw ProtocolError.malformedStartup
        }
        if let expectedPID, Int(expectedPID) != pid { throw ProtocolError.pidMismatch(expected: expectedPID, received: pid) }
        guard let components = URLComponents(string: baseURL),
              components.scheme == "http",
              components.host == "127.0.0.1",
              components.port != nil,
              components.port != 0,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              let url = components.url else { throw ProtocolError.invalidOrigin(baseURL) }
        return ValidatedSidecar(baseURL: url, token: token, pid: pid, serverVersion: serverVersion)
    }
}

public struct SidecarFatal: Sendable, Codable, Equatable {
    public let type: String
    public let protocolVersion: Int
    public let code: String
    public let message: String

    enum CodingKeys: String, CodingKey {
        case type, code, message
        case protocolVersion = "protocol_version"
    }
}

public enum StartupMessage: Sendable, Equatable {
    case ready(SidecarReady)
    case fatal(SidecarFatal)

    public static func parse(_ line: Data) throws -> StartupMessage {
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(StartupEnvelope.self, from: line)
        switch envelope.type {
        case "ready": return .ready(try decoder.decode(SidecarReady.self, from: line))
        case "fatal": return .fatal(try decoder.decode(SidecarFatal.self, from: line))
        default: throw ProtocolError.malformedStartup
        }
    }

    private struct StartupEnvelope: Decodable { let type: String }
}

public struct ValidatedSidecar: Sendable, Equatable {
    public let baseURL: URL
    public let token: String
    public let pid: Int
    public let serverVersion: String
}
