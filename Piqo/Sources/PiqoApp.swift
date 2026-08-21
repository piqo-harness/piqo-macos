import SwiftUI
import SwiftData
import Observation
import PiqoProtocol
import PiqoRuntime
import PiqoData
import PiqoPresentation

@main
struct PiqoApp: App {
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(coordinator)
                .modelContainer(for: SessionMetadata.self)
        }
        WindowGroup("Conversation", for: String.self) { $sessionID in
            if let sessionID {
                SessionWindow(sessionID: sessionID)
                    .environment(coordinator)
                    .modelContainer(for: SessionMetadata.self)
            } else { ContentUnavailableView("No conversation selected", systemImage: "bubble.left.and.bubble.right") }
        }
        Settings {
            SettingsView()
                .environment(coordinator)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { coordinator.updater.checkForUpdates() }
            }
        }
    }
}

@MainActor @Observable
final class AppCoordinator {
    enum Phase: Equatable { case launching, ready, configurationRequired, offline(String), failed(String) }

    var phase: Phase = .launching
    var sessions: [SessionSummary] = []
    var providers: [Provider] = []
    var nextCursor: String?
    let supervisor = SidecarSupervisor()
    let configuration = TOMLConfigurationStore()
    let updater = PiqoUpdater()
    private(set) var api: PiqoAPIClient?
    private(set) var streams: SessionStreamCoordinator?

    func launch() async {
        guard case .launching = phase else { return }
        do {
            let client = try await supervisor.start(executableURL: sidecarURL())
            api = client; streams = SessionStreamCoordinator(api: client)
            try await refresh()
            phase = providers.isEmpty ? .configurationRequired : .ready
        } catch let failure as SidecarFailure {
            if case .fatal(let code, _) = failure, code == "config_invalid" {
                phase = .configurationRequired
            } else {
                phase = .failed(failure.localizedDescription)
            }
        } catch { phase = .failed(error.localizedDescription) }
    }

    func refresh() async throws {
        guard let api else { return }
        let list = try await api.sessions(cursor: nil)
        sessions = list.sessions; nextCursor = list.nextCursor
        providers = try await api.providers()
    }

    func loadMoreSessions() async {
        guard let api, let nextCursor else { return }
        do { let page = try await api.sessions(cursor: nextCursor); sessions += page.sessions; self.nextCursor = page.nextCursor } catch { phase = .failed(error.localizedDescription) }
    }

    func createConversation(prompt: String, workspace: URL, provider: String, model: String, agent: String?, variant: String?, body: JSONValue) async throws -> String {
        guard let api, let streams else { throw PiqoAPIError.invalidResponse }
        let title = String(prompt.split(separator: "\n").first ?? "New conversation".prefix(80))
        let session = try await api.createSession(title: title)
        let viewModel = SessionViewModel(sessionID: session.id, api: api, streams: streams)
        await viewModel.load()
        await viewModel.send(prompt: prompt, provider: provider, model: model, agent: agent, variant: variant, body: body)
        sessions.insert(session, at: 0)
        return session.id
    }

    func makeSessionViewModel(_ sessionID: String) -> SessionViewModel? {
        guard let api, let streams else { return nil }
        return SessionViewModel(sessionID: sessionID, api: api, streams: streams)
    }

    func diagnostics() async -> [String] { await supervisor.diagnostics.snapshot() }

    private func sidecarURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["PIQO_SIDECAR_PATH"] { return URL(fileURLWithPath: override) }
        return Bundle.main.bundleURL.appending(path: "Contents/Helpers/piqo-server")
    }
}
