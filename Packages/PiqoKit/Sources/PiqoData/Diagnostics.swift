import Foundation

public enum Exporter {
    public static func redactedDiagnostics(lines: [String]) -> Data {
        let sensitive = ["authorization", "bearer ", "api_key", "token"]
        let filtered = lines.map { line in
            sensitive.reduce(line) { partial, word in
                partial.replacingOccurrences(of: "(?i)\(word)[^\\s\\\"]*", with: "[REDACTED]", options: .regularExpression)
            }
        }
        return filtered.joined(separator: "\n").data(using: .utf8) ?? Data()
    }

    public static func write(_ data: Data, named name: String, to directory: URL) throws -> URL {
        let url = directory.appending(path: name)
        try data.write(to: url, options: .atomic)
        return url
    }
}
