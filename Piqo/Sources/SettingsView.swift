import SwiftUI
import AppKit
import PiqoData

struct SettingsView: View {
    @Environment(AppCoordinator.self) private var app
    @State private var document = ConfigurationDocument(source: "")
    @State private var error: String?
    @State private var selectedProvider: ProviderConfiguration?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedProvider) { ForEach(document.providers) { provider in Text(provider.name).tag(provider) } }
                .toolbar { Button("Add provider", systemImage: "plus") { selectedProvider = ProviderConfiguration(name: "new-provider", baseURL: "") } }
        } detail: {
            Form {
                if let provider = selectedProvider { ProviderEditor(provider: Binding(get: { provider }, set: { selectedProvider = $0 })) }
                Section("Raw piqo.toml") { TextEditor(text: $document.source).font(.body.monospaced()).frame(minHeight: 220) }
                if let error { Text(error).foregroundStyle(.red) }
                HStack { Button("Open in default editor") { openConfiguration() }; Spacer(); Button("Save") { save() }.keyboardShortcut("s") }
            }.padding().task { load() }
        }
        .frame(width: 760, height: 520)
    }
    private func load() { Task { do { document = try await app.configuration.load() } catch { self.error = error.localizedDescription } } }
    private func save() { Task { do { try await app.configuration.save(document); error = nil } catch { self.error = error.localizedDescription } } }
    private func openConfiguration() { Task { NSWorkspace.shared.open(await app.configuration.configurationURL()) } }
}

private struct ProviderEditor: View {
    @Binding var provider: ProviderConfiguration
    var body: some View {
        Section("Provider") { TextField("Name", text: $provider.name); TextField("Base URL", text: $provider.baseURL); Picker("Protocol", selection: $provider.protocolName) { Text("Chat Completions").tag("chat_completions"); Text("Responses").tag("responses") }; SecureField("API key", text: Binding(get: { provider.apiKey ?? "" }, set: { provider.apiKey = $0.isEmpty ? nil : $0 })); Stepper("Connect timeout: \(provider.connectTimeoutSeconds)s", value: $provider.connectTimeoutSeconds, in: 1...120) }
    }
}
