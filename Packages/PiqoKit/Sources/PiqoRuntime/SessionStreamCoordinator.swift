import Foundation
import PiqoProtocol

/// Fans one durable SSE connection out to every window showing the same session.
public actor SessionStreamCoordinator {
    private var listeners: [String: [UUID: AsyncStream<PiqoEvent>.Continuation]] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    private var checkpoints: [String: UInt64] = [:]
    private let api: PiqoAPIClient

    public init(api: PiqoAPIClient) { self.api = api }

    public func subscribe(sessionID: String, after eventID: UInt64 = 0) -> AsyncStream<PiqoEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            listeners[sessionID, default: [:]][id] = continuation
            checkpoints[sessionID] = max(checkpoints[sessionID] ?? 0, eventID)
            if tasks[sessionID] == nil { start(sessionID: sessionID) }
            continuation.onTermination = { [weak self] _ in Task { await self?.remove(id, sessionID: sessionID) } }
        }
    }

    private func start(sessionID: String) {
        tasks[sessionID] = Task { [weak self] in
            guard let self else { return }
            var retry = 0
            while !Task.isCancelled {
                let checkpoint = await self.checkpoints[sessionID] ?? 0
                do {
                    for try await event in await self.api.stream(sessionID: sessionID, after: checkpoint) {
                        await self.publish(event)
                    }
                    return
                } catch {
                    retry += 1
                    let seconds = min(8.0, pow(2.0, Double(retry - 1)) * 0.5) * Double.random(in: 0.8...1.2)
                    try? await Task.sleep(for: .milliseconds(Int64(seconds * 1_000)))
                }
            }
        }
    }
    private func publish(_ event: PiqoEvent) {
        guard event.id > (checkpoints[event.sessionID] ?? 0) else { return }
        checkpoints[event.sessionID] = event.id
        for continuation in listeners[event.sessionID]?.values ?? [:].values { continuation.yield(event) }
    }
    private func remove(_ id: UUID, sessionID: String) {
        listeners[sessionID]?[id] = nil
        if listeners[sessionID]?.isEmpty == true { tasks[sessionID]?.cancel(); tasks[sessionID] = nil; listeners[sessionID] = nil }
    }
}
