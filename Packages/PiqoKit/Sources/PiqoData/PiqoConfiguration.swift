import Foundation
import TOML
import TreeSitterTOML

public struct ProviderConfiguration: Sendable, Identifiable, Equatable, Hashable {
    public var name: String
    public var baseURL: String
    public var protocolName: String
    public var apiKey: String?
    public var connectTimeoutSeconds: Int
    public var headers: [String: String]
    public var id: String { name }

    public init(name: String, baseURL: String, protocolName: String = "chat_completions", apiKey: String? = nil, connectTimeoutSeconds: Int = 10, headers: [String: String] = [:]) {
        self.name = name; self.baseURL = baseURL; self.protocolName = protocolName; self.apiKey = apiKey; self.connectTimeoutSeconds = connectTimeoutSeconds; self.headers = headers
    }
}

public struct ConfigurationDocument: Sendable, Equatable {
    public var source: String
    public var providers: [ProviderConfiguration]
    public var defaultsJSON: String
    public var modelsJSON: String
    public var agentsJSON: String
    public var variantsJSON: String
    public init(source: String, providers: [ProviderConfiguration] = [], defaultsJSON: String = "{}", modelsJSON: String = "{}", agentsJSON: String = "{}", variantsJSON: String = "{}") {
        self.source = source; self.providers = providers; self.defaultsJSON = defaultsJSON; self.modelsJSON = modelsJSON; self.agentsJSON = agentsJSON; self.variantsJSON = variantsJSON
    }
}

public enum ConfigurationError: LocalizedError, Sendable, Equatable {
    case invalidTOML(String)
    case ambiguousPatch(String)
    case externalChange

    public var errorDescription: String? {
        switch self { case .invalidTOML(let message), .ambiguousPatch(let message): message; case .externalChange: "piqo.toml changed outside Piqo. Reload it before saving." }
    }
}

/// Owns only targeted source edits. Unrecognised sections, comments, and order remain untouched.
public actor TOMLConfigurationStore {
    public let url: URL
    private var loadedSource: String?

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        url = home.appending(path: ".config/piqo/piqo.toml")
    }

    public func configurationURL() -> URL { url }

    public func load() throws -> ConfigurationDocument {
        let source = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try validate(source)
        loadedSource = source
        return ConfigurationDocument(source: source, providers: parseProviders(source))
    }

    public func save(_ document: ConfigurationDocument) throws {
        let current = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        guard loadedSource.map({ current == $0 }) ?? current.isEmpty else { throw ConfigurationError.externalChange }
        try validate(document.source)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if FileManager.default.fileExists(atPath: url.path) {
            let backup = url.deletingPathExtension().appendingPathExtension("toml.last-valid")
            try? FileManager.default.copyItem(at: url, to: backup)
        }
        let temporary = directory.appending(path: ".piqo.toml.\(UUID().uuidString).tmp")
        try document.source.data(using: .utf8)?.write(to: temporary, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary, backupItemName: nil, options: [])
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }
        loadedSource = document.source
    }

    public func restoreLastValid() throws {
        let backup = url.deletingPathExtension().appendingPathExtension("toml.last-valid")
        guard FileManager.default.fileExists(atPath: backup.path) else { throw ConfigurationError.invalidTOML("No valid piqo.toml backup is available.") }
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: backup, to: url)
        loadedSource = try String(contentsOf: url, encoding: .utf8)
    }

    /// Updates scalar provider fields while retaining unrelated lines and comments.
    public func patchProvider(_ provider: ProviderConfiguration, in document: ConfigurationDocument) throws -> ConfigurationDocument {
        let header = "[providers.\"\(provider.name)\"]"
        let bareHeader = "[providers.\(provider.name)]"
        let lines = document.source.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == header || $0.trimmingCharacters(in: .whitespaces) == bareHeader }) else {
            var appended = document.source
            if !appended.isEmpty, !appended.hasSuffix("\n") { appended += "\n" }
            appended += "\n\(header)\nbase_url = \"\(escape(provider.baseURL))\"\nprotocol = \"\(escape(provider.protocolName))\"\nconnect_timeout_seconds = \(provider.connectTimeoutSeconds)\n"
            if let apiKey = provider.apiKey, !apiKey.isEmpty { appended += "api_key = \"\(escape(apiKey))\"\n" }
            return ConfigurationDocument(source: appended, providers: parseProviders(appended))
        }
        let end = lines[(start + 1)...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") }) ?? lines.endIndex
        var replacement = Array(lines[start..<end])
        replace(&replacement, key: "base_url", value: "\"\(escape(provider.baseURL))\"")
        replace(&replacement, key: "protocol", value: "\"\(escape(provider.protocolName))\"")
        replace(&replacement, key: "connect_timeout_seconds", value: String(provider.connectTimeoutSeconds))
        if let apiKey = provider.apiKey, !apiKey.isEmpty { replace(&replacement, key: "api_key", value: "\"\(escape(apiKey))\"") }
        var updated = lines; updated.replaceSubrange(start..<end, with: replacement)
        let source = updated.joined(separator: "\n")
        try validate(source)
        return ConfigurationDocument(source: source, providers: parseProviders(source))
    }

    private func validate(_ source: String) throws {
        guard !source.isEmpty else { return }
        do { _ = try TOMLDecoder().decode(TOMLValidation.self, from: source) }
        catch { throw ConfigurationError.invalidTOML(error.localizedDescription) }
    }
    private func parseProviders(_ source: String) -> [ProviderConfiguration] {
        var providers: [ProviderConfiguration] = []; var current: ProviderConfiguration?
        func finish() { if let current { providers.append(current) } }
        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[providers.") && line.hasSuffix("]") && !line.contains(".headers]") {
                finish()
                let name = line.dropFirst("[providers.".count).dropLast().trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                current = ProviderConfiguration(name: name, baseURL: "")
            } else if let equals = line.firstIndex(of: "="), var provider = current {
                let key = line[..<equals].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                switch key { case "base_url": provider.baseURL = value; case "protocol": provider.protocolName = value; case "api_key": provider.apiKey = value; case "connect_timeout_seconds": provider.connectTimeoutSeconds = Int(value) ?? 10; default: break }
                current = provider
            }
        }
        finish(); return providers
    }
    private func replace(_ lines: inout [String], key: String, value: String) {
        if let index = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("\(key) =") }) {
            let comment = lines[index].split(separator: "#", maxSplits: 1).dropFirst().first.map { " #\($0)" } ?? ""
            lines[index] = "\(key) = \(value)\(comment)"
        } else { lines.append("\(key) = \(value)") }
    }
    private func escape(_ value: String) -> String { value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
}

private struct TOMLValidation: Decodable {}
