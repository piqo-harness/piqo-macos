import SwiftUI
import SwiftData
import PiqoProtocol
import PiqoData
import PiqoPresentation

struct SessionWindow: View {
    @Environment(AppCoordinator.self) private var app
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Query private var metadata: [SessionMetadata]
    let sessionID: String
    @State private var viewModel: SessionViewModel?
    @State private var inspectorVisible = true

    var body: some View {
        Group {
            if let viewModel {
                ConversationView(viewModel: viewModel, inspectorVisible: $inspectorVisible, fork: { eventID in fork(eventID, using: viewModel) })
                    .inspector(isPresented: $inspectorVisible) { InspectorView(viewModel: viewModel, app: app) }
                    .task { await viewModel.load() }
            } else { ProgressView("Opening conversation…").task { viewModel = app.makeSessionViewModel(sessionID) } }
        }
        .frame(minWidth: 760, minHeight: 560)
    }

    private func fork(_ eventID: UInt64, using viewModel: SessionViewModel) {
        Task {
            do {
                let child = try await viewModel.fork(at: eventID)
                let workspace = metadata.first(where: { $0.sessionID == sessionID })?.workspaceURL
                modelContext.insert(SessionMetadata(sessionID: child.id, workspaceURL: workspace))
                openWindow(id: "Conversation", value: child.id)
            } catch {
                viewModel.showError(error)
            }
        }
    }
}

private struct ConversationView: View {
    @Bindable var viewModel: SessionViewModel
    @Binding var inspectorVisible: Bool
    let fork: (UInt64) -> Void
    @State private var prompt = ""
    @State private var provider = ""
    @State private var model = ""
    @State private var agent = ""
    @State private var variant = ""
    @State private var bodyJSON = "{}"

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView { LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(viewModel.state.messages) { MessageBubble(message: $0, onFork: fork) }
                    ForEach(viewModel.state.runs.filter { $0.status == "queued" }) { run in PendingRunRow(run: run, cancel: { Task { await viewModel.cancel(run) } }) }
                    if let blocked = viewModel.state.blockedReason { Label(blocked, systemImage: "hand.raised.fill").padding().frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10)) }
                }.padding() }
                .onChange(of: viewModel.state.messages.count) { _, _ in if let id = viewModel.state.messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } } }
            }
            Divider(); composer
        }
        .navigationTitle(viewModel.summary?.title ?? "Conversation")
        .toolbar { ToolbarItem { Button("Inspector", systemImage: "sidebar.right") { inspectorVisible.toggle() } } }
        .onAppear { if provider.isEmpty { provider = viewModel.state.runs.last?.provider ?? ""; model = viewModel.state.runs.last?.model ?? "" } }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { TextField("Provider", text: $provider).frame(width: 150); TextField("Model", text: $model).frame(width: 180); TextField("Agent", text: $agent).frame(width: 100); TextField("Variant", text: $variant).frame(width: 100); Spacer() }
            TextEditor(text: $prompt).font(.body).frame(minHeight: 70, maxHeight: 120)
            DisclosureGroup("Advanced request JSON") { TextEditor(text: $bodyJSON).font(.body.monospaced()).frame(height: 90) }
            HStack { Spacer(); Button("Send", systemImage: "arrow.up.circle.fill") { send() }.disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || provider.isEmpty || model.isEmpty) }
        }.padding()
    }
    private func send() { guard let data = bodyJSON.data(using: .utf8), let body = try? JSONDecoder().decode(JSONValue.self, from: data) else { return }; let message = prompt; prompt = ""; Task { await viewModel.send(prompt: message, provider: provider, model: model, agent: agent.nilIfEmpty, variant: variant.nilIfEmpty, body: body) } }
}

private struct MessageBubble: View {
    let message: ConversationMessage
    let onFork: (UInt64) -> Void
    @State private var showSource = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(message.role.capitalized).font(.caption.weight(.semibold)).foregroundStyle(.secondary); Spacer(); if let eventID = message.completionEventID { Button("Fork", systemImage: "arrow.triangle.branch") { onFork(eventID) }.labelStyle(.iconOnly) } }
            if showSource { Text(message.text).font(.body.monospaced()).textSelection(.enabled) }
            else { MarkdownText(message.text) }
            ForEach(Array(message.jsonBlocks.enumerated()), id: \.offset) { _, json in Text(json.prettyPrinted()).font(.body.monospaced()).textSelection(.enabled).padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 6)) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(message.role == "user" ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.quaternary.opacity(0.4)), in: RoundedRectangle(cornerRadius: 12))
        .contextMenu { Button(showSource ? "Render Markdown" : "Show source") { showSource.toggle() }; Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string) } }
        .id(message.id)
    }
}

private struct MarkdownText: View {
    let source: String
    init(_ source: String) { self.source = source }
    var body: some View {
        Group {
            if let attributed = try? AttributedString(markdown: source) {
                Text(attributed)
            } else {
                Text(source)
            }
        }
        .textSelection(.enabled)
    }
}

private struct PendingRunRow: View { let run: PendingRun; let cancel: () -> Void; var body: some View { HStack { ProgressView(); Text(run.prompt.isEmpty ? "Queued run" : run.prompt).lineLimit(1); Spacer(); Button("Cancel", action: cancel) }.padding(10).background(.tertiary, in: RoundedRectangle(cornerRadius: 9)) } }

private struct InspectorView: View {
    let viewModel: SessionViewModel; let app: AppCoordinator
    @State private var tab = "Runs"; @State private var logs: [String] = []
    var body: some View {
        Picker("Inspector", selection: $tab) { Text("Runs").tag("Runs"); Text("Events").tag("Events"); Text("Logs").tag("Logs") }.pickerStyle(.segmented).padding()
        Group { switch tab { case "Runs": List(viewModel.state.runs) { run in VStack(alignment: .leading) { Text(run.status).font(.caption).foregroundStyle(.secondary); Text("\(run.provider) · \(run.model)"); Text(run.prompt).lineLimit(3) } }
            case "Events": List(viewModel.state.events) { event in VStack(alignment: .leading) { Text(event.type).font(.caption.weight(.bold)); Text(event.data.prettyPrinted()).font(.caption.monospaced()) } }
            default: ScrollView { Text(logs.joined()).font(.caption.monospaced()).textSelection(.enabled).padding() }.task { logs = await app.diagnostics() }
        } }
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
