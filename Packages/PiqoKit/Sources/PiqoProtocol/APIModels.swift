import Foundation

public struct APIErrorEnvelope: Sendable, Codable, Equatable {
    public let error: APIErrorBody
}

public struct APIErrorBody: Sendable, Codable, Equatable {
    public let code: String
    public let message: String
}

public struct Health: Sendable, Codable, Equatable {
    public let status: String
    public let serverVersion: String
    public let apiVersion: String

    enum CodingKeys: String, CodingKey {
        case status
        case serverVersion = "server_version"
        case apiVersion = "api_version"
    }
}

public struct SessionSummary: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public let title: String?
    public let parentSessionID: String?
    public let forkedAtEventID: UInt64?
    public let createdAt: String
    public let updatedAt: String
    public let phase: String
    public let revision: UInt64
    public let lastEventID: UInt64
    public let projection: JSONValue?

    enum CodingKeys: String, CodingKey {
        case id, title, phase, revision, projection
        case parentSessionID = "parent_session_id"
        case forkedAtEventID = "forked_at_event_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastEventID = "last_event_id"
    }
}

public struct SessionList: Sendable, Codable, Equatable {
    public let sessions: [SessionSummary]
    public let nextCursor: String?
    enum CodingKeys: String, CodingKey { case sessions; case nextCursor = "next_cursor" }
}

public struct ProviderCatalog: Sendable, Codable, Equatable {
    public let providers: [Provider]
}

public struct Provider: Sendable, Codable, Identifiable, Equatable {
    public let name: String
    public let protocolName: String
    public let streaming: Bool
    public let nonStreaming: Bool
    public let models: [String]
    public var id: String { name }
    enum CodingKeys: String, CodingKey {
        case name, streaming, models
        case protocolName = "protocol"
        case nonStreaming = "non_streaming"
    }
}

public struct CreateSession: Sendable, Codable {
    public let title: String?
    public init(title: String? = nil) { self.title = title }
}

public struct CreateRun: Sendable, Codable {
    public let provider: String
    public let model: String
    public let input: JSONValue
    public let agent: String?
    public let variant: String?
    public let body: JSONValue
    public init(provider: String, model: String, input: JSONValue, agent: String? = nil, variant: String? = nil, body: JSONValue = .object([:])) {
        self.provider = provider; self.model = model; self.input = input; self.agent = agent; self.variant = variant; self.body = body
    }
}

public struct RunAccepted: Sendable, Codable, Equatable {
    public let sessionID: String
    public let runID: String
    public let status: String
    public let eventsURL: String
    public let streamURL: String
    enum CodingKeys: String, CodingKey {
        case status
        case sessionID = "session_id"; case runID = "run_id"
        case eventsURL = "events_url"; case streamURL = "stream_url"
    }
}

public struct RunResponse: Sendable, Codable, Equatable {
    public let sessionID: String
    public let run: Run
    enum CodingKeys: String, CodingKey { case run; case sessionID = "session_id" }
}

public struct Run: Sendable, Codable, Identifiable, Equatable {
    public let runID: String
    public let retryOf: String?
    public let provider: String
    public let model: String
    public let request: JSONValue
    public let status: String
    public let attemptID: String?
    public let attempts: UInt32
    public let error: String?
    public var id: String { runID }
    enum CodingKeys: String, CodingKey {
        case provider, model, request, status, attempts, error
        case runID = "run_id"; case retryOf = "retry_of"; case attemptID = "attempt_id"
    }
}

public struct PiqoEvent: Sendable, Codable, Identifiable, Equatable {
    public let id: UInt64
    public let sessionID: String
    public let schemaVersion: UInt16
    public let occurredAt: String
    public let type: String
    public let data: JSONValue
    enum CodingKeys: String, CodingKey {
        case id, type, data
        case sessionID = "session_id"; case schemaVersion = "schema_version"; case occurredAt = "occurred_at"
    }
    public var isTerminalRunEvent: Bool { ["run_completed", "run_failed", "run_cancelled", "run_interrupted"].contains(type) }
    /// New server event names are retained verbatim instead of rejecting a stream.
    public var kind: PiqoEventKind { PiqoEventKind(type: type, data: data) }
}

public enum PiqoEventKind: Sendable, Equatable {
    case messageStarted, messageContentAppended, messageCompleted, messageInterrupted
    case runQueued, runStarted, runCompleted, runFailed, runCancelled, runInterrupted, runRequiresAction
    case permissionRequested
    case unknown(type: String, data: JSONValue)

    init(type: String, data: JSONValue) {
        switch type {
        case "message_started": self = .messageStarted
        case "message_content_appended": self = .messageContentAppended
        case "message_completed": self = .messageCompleted
        case "message_interrupted": self = .messageInterrupted
        case "run_queued": self = .runQueued
        case "run_started": self = .runStarted
        case "run_completed": self = .runCompleted
        case "run_failed": self = .runFailed
        case "run_cancelled": self = .runCancelled
        case "run_interrupted": self = .runInterrupted
        case "run_requires_action": self = .runRequiresAction
        case "permission_requested": self = .permissionRequested
        default: self = .unknown(type: type, data: data)
        }
    }
}

public struct EventsPage: Sendable, Codable, Equatable { public let events: [PiqoEvent] }
