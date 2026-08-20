import Testing
import Foundation
@testable import PiqoData

@Test func patchesKnownProviderWithoutDiscardingComment() async throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let store = TOMLConfigurationStore(home: home)
        let source = "# private provider\n[providers.local]\nbase_url = \"http://old\" # keep this\nprotocol = \"chat_completions\"\ncustom = true\n"
        var document = ConfigurationDocument(source: source)
        document = try await store.patchProvider(ProviderConfiguration(name: "local", baseURL: "http://new"), in: document)
        #expect(document.source.contains("# keep this"))
        #expect(document.source.contains("custom = true"))
        try await store.save(document)
        let configurationURL = await store.configurationURL()
        let attributes = try FileManager.default.attributesOfItem(atPath: configurationURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func refusesToOverwriteExternalConfigurationChange() async throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let store = TOMLConfigurationStore(home: home)
        let first = ConfigurationDocument(source: "[providers.local]\nbase_url = \"http://one\"\n")
        try await store.save(first)
        _ = try await store.load()
        let url = await store.configurationURL()
        try "[providers.local]\nbase_url = \"http://external\"\n".write(to: url, atomically: true, encoding: .utf8)
        do {
            try await store.save(first)
            Issue.record("Expected external-change protection")
        } catch let error as ConfigurationError {
            #expect(error == .externalChange)
        }
}
