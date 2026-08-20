import Foundation
import PiqoProtocol

public enum PiqoAPIError: LocalizedError, Sendable, Equatable {
    case invalidResponse
    case server(status: Int, code: String, message: String)
    case incompatibleHealth
    case invalidStream

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "The sidecar returned an invalid HTTP response."
        case .server(_, _, let message): message
        case .incompatibleHealth: "The sidecar health response is not compatible with API v1."
        case .invalidStream: "The sidecar returned an invalid event stream."
        }
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? { nil }
}

public actor PiqoAPIClient {
    public let origin: URL
    private let token: String
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(sidecar: ValidatedSidecar) {
        origin = sidecar.baseURL
        token = sidecar.token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    public func health() async throws -> Health {
        let health: Health = try await get("/api/v1/health")
        guard health.status == "ok", health.apiVersion == "v1" else { throw PiqoAPIError.incompatibleHealth }
        return health
    }

    public func providers() async throws -> [Provider] { try await get("/api/v1/providers", as: ProviderCatalog.self).providers }
    public func sessions(cursor: String? = nil, limit: Int = 50) async throws -> SessionList {
        var components = URLComponents(url: endpoint("/api/v1/sessions"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: String(min(max(limit, 1), 200)))] + (cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? [])
        return try await send(URLRequest(url: components.url!), as: SessionList.self)
    }
    public func session(_ id: String) async throws -> SessionSummary { try await get("/api/v1/sessions/\(escaped(id))") }
    public func createSession(title: String?) async throws -> SessionSummary { try await post("/api/v1/sessions", body: CreateSession(title: title), as: SessionSummary.self) }
    public func createRun(sessionID: String, request: CreateRun) async throws -> RunAccepted { try await post("/api/v1/sessions/\(escaped(sessionID))/runs", body: request, as: RunAccepted.self) }
    public func run(sessionID: String, runID: String) async throws -> RunResponse { try await get("/api/v1/sessions/\(escaped(sessionID))/runs/\(escaped(runID))") }
    public func cancel(sessionID: String, runID: String) async throws { try await emptyPost("/api/v1/sessions/\(escaped(sessionID))/runs/\(escaped(runID))/cancel") }
    public func retry(sessionID: String, runID: String) async throws -> RunAccepted { try await emptyPost("/api/v1/sessions/\(escaped(sessionID))/runs/\(escaped(runID))/retries", as: RunAccepted.self) }
    public func resume(sessionID: String) async throws { try await emptyPost("/api/v1/sessions/\(escaped(sessionID))/queue/resume") }
    public func fork(sessionID: String, at eventID: UInt64, title: String? = nil) async throws -> SessionSummary {
        try await post("/api/v1/sessions/\(escaped(sessionID))/forks", body: ForkRequest(atEventID: eventID, title: title), as: SessionSummary.self)
    }
    public func history(sessionID: String, after eventID: UInt64 = 0, limit: Int = 200) async throws -> [PiqoEvent] {
        var components = URLComponents(url: endpoint("/api/v1/sessions/\(escaped(sessionID))/events"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "after", value: String(eventID)), URLQueryItem(name: "limit", value: String(min(max(limit, 1), 200)))]
        return try await send(URLRequest(url: components.url!), as: EventsPage.self).events
    }

    public func stream(sessionID: String, after eventID: UInt64) -> AsyncThrowingStream<PiqoEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpoint("/api/v1/sessions/\(escaped(sessionID))/events/stream"))
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue(String(eventID), forHTTPHeaderField: "Last-Event-ID")
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw PiqoAPIError.invalidStream }
                    var parser = SSEParser()
                    for try await byte in bytes {
                        for frame in try parser.ingest(Data([byte])) where !frame.data.isEmpty {
                            let event = try decoder.decode(PiqoEvent.self, from: Data(frame.data.utf8))
                            guard String(event.id) == frame.id, frame.event == event.type else { throw PiqoAPIError.invalidStream }
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T { try await send(URLRequest(url: endpoint(path)), as: type) }
    private func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body, as type: Response.Type) async throws -> Response {
        var request = URLRequest(url: endpoint(path)); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try encoder.encode(body)
        return try await send(request, as: type)
    }
    private func emptyPost(_ path: String) async throws { var request = URLRequest(url: endpoint(path)); request.httpMethod = "POST"; _ = try await sendEmpty(request) }
    private func emptyPost<T: Decodable>(_ path: String, as type: T.Type) async throws -> T { var request = URLRequest(url: endpoint(path)); request.httpMethod = "POST"; return try await send(request, as: type) }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, _) = try await sendRaw(request)
        return try decoder.decode(T.self, from: data)
    }
    private func sendEmpty(_ request: URLRequest) async throws -> HTTPURLResponse { let (_, response) = try await sendRaw(request); return response }
    private func sendRaw(_ initialRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = initialRequest
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PiqoAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data)
            throw PiqoAPIError.server(status: http.statusCode, code: envelope?.error.code ?? "unknown", message: envelope?.error.message ?? "HTTP \(http.statusCode)")
        }
        return (data, http)
    }
    private func endpoint(_ path: String) -> URL { origin.appending(path: path) }
    private func escaped(_ identifier: String) -> String { identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? identifier }
}

private struct ForkRequest: Codable { let atEventID: UInt64; let title: String?; enum CodingKeys: String, CodingKey { case title; case atEventID = "at_event_id" } }
