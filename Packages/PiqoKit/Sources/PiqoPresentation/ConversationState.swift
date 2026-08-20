import Foundation
import Observation
import PiqoProtocol
import PiqoRuntime

public struct ConversationMessage: Identifiable, Sendable, Equatable {
    public var id: String
    public var role: String
    public var author: String
    public var text: String
    public var jsonBlocks: [JSONValue]
    public var completed: Bool
    public var interrupted: Bool
    public var completionEventID: UInt64?
}

public struct PendingRun: Identifiable, Sendable, Equatable {
    public var id: String
    public var prompt: String
    public var status: String
    public var provider: String
    public var model: String
}

@MainActor @Observable
public final class ConversationState {
    public private(set) var messages: [ConversationMessage] = []
    public private(set) var runs: [PendingRun] = []
    public private(set) var events: [PiqoEvent] = []
    public private(set) var blockedReason: String?
    public private(set) var lastProcessedEventID: UInt64 = 0

    public init() {}

    public func reset() { messages = []; runs = []; events = []; blockedReason = nil; lastProcessedEventID = 0 }
    public func apply(_ event: PiqoEvent) {
        guard event.id > lastProcessedEventID else { return }
        events.append(event)
        switch event.type {
        case "message_started":
            guard let data = event.data.objectValue,
                  let messageID = data["message_id"]?.stringValue else { break }
            messages.append(ConversationMessage(id: messageID, role: data["role"]?.stringValue ?? "system", author: data["author"]?.stringValue ?? "", text: "", jsonBlocks: [], completed: false, interrupted: false, completionEventID: nil))
        case "message_content_appended":
            guard let data = event.data.objectValue,
                  let messageID = data["message_id"]?.stringValue,
                  let block = data["block"]?.objectValue,
                  let index = messages.firstIndex(where: { $0.id == messageID }) else { break }
            if block["kind"]?.stringValue == "text" { messages[index].text += block["value"]?.stringValue ?? "" }
            else if let value = block["value"] { messages[index].jsonBlocks.append(value) }
        case "message_completed", "message_interrupted":
            guard let messageID = event.data.objectValue?["message_id"]?.stringValue,
                  let index = messages.firstIndex(where: { $0.id == messageID }) else { break }
            messages[index].completed = event.type == "message_completed"
            messages[index].interrupted = event.type == "message_interrupted"
            messages[index].completionEventID = event.id
        case "run_queued":
            guard let data = event.data.objectValue, let runID = data["run_id"]?.stringValue else { break }
            let request = data["request"]?.objectValue
            runs.append(PendingRun(id: runID, prompt: request?["input"]?.stringValue ?? "", status: "queued", provider: data["provider"]?.stringValue ?? "", model: data["model"]?.stringValue ?? ""))
        case "run_started", "run_completed", "run_failed", "run_cancelled", "run_interrupted", "run_requires_action":
            guard let runID = event.data.objectValue?["run_id"]?.stringValue,
                  let index = runs.firstIndex(where: { $0.id == runID }) else { break }
            runs[index].status = event.type.replacingOccurrences(of: "run_", with: "")
            if event.type == "run_requires_action" { blockedReason = "This run requires an action that API v1 cannot submit." }
        case "permission_requested": blockedReason = "This permission request cannot be resolved by API v1."
        default: break
        }
        lastProcessedEventID = event.id
    }
}

@MainActor @Observable
public final class SessionViewModel {
    public let sessionID: String
    public let state = ConversationState()
    public private(set) var summary: SessionSummary?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    private var streamTask: Task<Void, Never>?
    private let api: PiqoAPIClient
    private let streams: SessionStreamCoordinator

    public init(sessionID: String, api: PiqoAPIClient, streams: SessionStreamCoordinator) { self.sessionID = sessionID; self.api = api; self.streams = streams }
    public func load() async {
        isLoading = true; defer { isLoading = false }
        do {
            summary = try await api.session(sessionID)
            let history = try await api.history(sessionID: sessionID)
            state.reset(); history.forEach(state.apply)
            streamTask?.cancel()
            let stream = await streams.subscribe(sessionID: sessionID, after: state.lastProcessedEventID)
            streamTask = Task { [weak self] in for await event in stream { await MainActor.run { self?.state.apply(event) } } }
        } catch { errorMessage = error.localizedDescription }
    }

    public func send(prompt: String, provider: String, model: String, agent: String?, variant: String?, body: JSONValue) async {
        do { _ = try await api.createRun(sessionID: sessionID, request: CreateRun(provider: provider, model: model, input: .string(prompt), agent: agent, variant: variant, body: body)) }
        catch { errorMessage = error.localizedDescription }
    }
    public func cancel(_ run: PendingRun) async { do { try await api.cancel(sessionID: sessionID, runID: run.id) } catch { errorMessage = error.localizedDescription } }
    public func retry(_ run: PendingRun) async { do { _ = try await api.retry(sessionID: sessionID, runID: run.id) } catch { errorMessage = error.localizedDescription } }
    public func showError(_ error: Error) { errorMessage = error.localizedDescription }
    public func fork(at completionEventID: UInt64) async throws -> SessionSummary {
        let child = try await api.fork(sessionID: sessionID, at: completionEventID)
        try await api.resume(sessionID: child.id)
        return child
    }
}

public enum TranscriptExporter {
    public static func markdown(title: String?, messages: [ConversationMessage]) -> String {
        var output = "# \(title ?? "Piqo session")\n\n"
        for message in messages {
            output += "## \(message.role.capitalized)\n\n\(message.text)\n\n"
            for json in message.jsonBlocks { output += "```json\n\(json.prettyPrinted())\n```\n\n" }
        }
        return output
    }
}
