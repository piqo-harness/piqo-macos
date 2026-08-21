import SwiftUI
import AppKit
import SwiftData
import PiqoProtocol
import PiqoData
import PiqoPresentation

struct RootView: View {
    @Environment(AppCoordinator.self) private var app
    @Environment(\.openWindow) private var openWindow
    @State private var search = ""
    @State private var showingDraft = false

    private var filteredSessions: [SessionSummary] {
        guard !search.isEmpty else { return app.sessions }
        return app.sessions.filter { ($0.title ?? "").localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationSplitView {
            List {
                Section("Conversations") {
                    ForEach(filteredSessions) { session in
                        Button { openWindow(id: "Conversation", value: session.id) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                let title = session.title ?? String(session.id.prefix(12))
                                Text(title).lineLimit(1)
                                Text(session.phase.replacingOccurrences(of: "_", with: " ")).font(.caption).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                    }
                    if app.nextCursor != nil { Button("Load more") { Task { await app.loadMoreSessions() } } }
                }
            }
            .searchable(text: $search, prompt: "Search conversations")
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("New conversation", systemImage: "square.and.pencil") { showingDraft = true } } }
            .navigationSplitViewColumnWidth(min: 300, ideal: 320)
        } detail: {
            Group {
                switch app.phase {
                case .launching: ProgressView("Starting Piqo…")
                case .ready: ContentUnavailableView("Select a conversation", systemImage: "bubble.left.and.bubble.right", description: Text("Or start a new conversation."))
                case .configurationRequired: ConfigurationRequiredView()
                case .offline(let message), .failed(let message): OfflineView(message: message)
                }
            }.frame(minWidth: 620, minHeight: 450)
        }
        .task { await app.launch() }
        .sheet(isPresented: $showingDraft) { DraftConversationSheet(isPresented: $showingDraft) { sessionID in openWindow(id: "Conversation", value: sessionID) } }
    }
}

private struct ConfigurationRequiredView: View {
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        VStack(spacing: 12) {
            ContentUnavailableView("Configure a provider", systemImage: "slider.horizontal.3", description: Text("Piqo is ready, but piqo.toml does not declare a usable provider."))
            Button("Open settings") { openSettings() }
        }
    }
}

private struct OfflineView: View {
    let message: String
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        VStack(spacing: 12) {
            ContentUnavailableView("Piqo is offline", systemImage: "bolt.slash", description: Text(message))
            Button("Open settings and diagnostics") { openSettings() }
        }
    }
}

struct DraftConversationSheet: View {
    @Environment(AppCoordinator.self) private var app
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool
    let opened: (String) -> Void
    @State private var workspace: URL?
    @State private var prompt = ""
    @State private var provider = ""
    @State private var model = ""
    @State private var agent = ""
    @State private var variant = ""
    @State private var bodyJSON = "{}"
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New conversation").font(.title2.weight(.semibold))
            HStack { Text(workspace?.path ?? "Choose a workspace").lineLimit(1); Spacer(); Button("Choose…") { chooseWorkspace() } }
            Picker("Provider", selection: $provider) { ForEach(app.providers) { Text($0.name).tag($0.name) } }
            Picker("Model", selection: $model) { ForEach(app.providers.first(where: { $0.name == provider })?.models ?? [], id: \.self) { Text($0).tag($0) } }
            TextField("Agent (optional)", text: $agent); TextField("Variant (optional)", text: $variant)
            TextEditor(text: $prompt).font(.body.monospaced()).frame(minHeight: 130).overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            DisclosureGroup("Advanced request JSON") { TextEditor(text: $bodyJSON).font(.body.monospaced()).frame(height: 100) }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack { Spacer(); Button("Cancel") { isPresented = false }; Button("Start") { start() }.keyboardShortcut(.defaultAction).disabled(workspace == nil || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || provider.isEmpty || model.isEmpty) }
        }
        .padding(24).frame(width: 560)
        .onAppear { provider = app.providers.first?.name ?? ""; model = app.providers.first?.models.first ?? "" }
    }

    private func chooseWorkspace() { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; if panel.runModal() == .OK { workspace = panel.url } }
    private func start() {
        guard let workspace, let data = bodyJSON.data(using: .utf8), let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { error = "The advanced request body must be valid JSON."; return }
        Task { do { let sessionID = try await app.createConversation(prompt: prompt, workspace: workspace, provider: provider, model: model, agent: agent.nilIfEmpty, variant: variant.nilIfEmpty, body: value); modelContext.insert(SessionMetadata(sessionID: sessionID, workspaceURL: workspace)); opened(sessionID); isPresented = false } catch { self.error = error.localizedDescription } }
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
