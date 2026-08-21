import Foundation

public struct SSEFrame: Sendable, Equatable {
    public var id: String?
    public var event: String?
    public var data: String
    public init(id: String? = nil, event: String? = nil, data: String = "") { self.id = id; self.event = event; self.data = data }
}

/// Standard SSE parser that accepts arbitrary byte boundaries and ignores comments.
public struct SSEParser: Sendable {
    private var pending = Data()
    private var frame = SSEFrame()

    public init() {}

    public mutating func ingest(_ bytes: Data) throws -> [SSEFrame] {
        pending.append(bytes)
        var frames: [SSEFrame] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            var line = pending.prefix(upTo: newline)
            pending.removeSubrange(...newline)
            if line.last == 0x0D { line.removeLast() }
            guard let string = String(data: line, encoding: .utf8) else {
                throw ProtocolError.malformedEvent("SSE stream was not UTF-8.")
            }
            if string.isEmpty {
                if frame.id != nil || frame.event != nil || !frame.data.isEmpty { frames.append(frame) }
                frame = SSEFrame()
            } else if string.hasPrefix(":") {
                continue
            } else if let separator = string.firstIndex(of: ":") {
                let field = String(string[..<separator])
                var value = String(string[string.index(after: separator)...])
                if value.first == " " { value.removeFirst() }
                switch field {
                case "id": frame.id = value
                case "event": frame.event = value
                case "data": frame.data += frame.data.isEmpty ? value : "\n\(value)"
                default: continue
                }
            }
        }
        return frames
    }
}
