import Testing
import Foundation
@testable import PiqoProtocol

@Test func validatesReadyMessageAndLoopbackOrigin() throws {
        let line = Data(#"{"type":"ready","protocol_version":1,"server_version":"0.1.0","api_version":"v1","pid":42,"base_url":"http://127.0.0.1:49152","token":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#.utf8)
        let startup = try StartupMessage.parse(line)
        guard case .ready(let ready) = startup else { Issue.record("Expected ready"); return }
        #expect(try ready.validated(expectedPID: 42).baseURL.host() == "127.0.0.1")
}

@Test func rejectsUnsafeReadyOrigin() throws {
        let ready = SidecarReady(type: "ready", protocolVersion: 1, serverVersion: "0", apiVersion: "v1", pid: 1, baseURL: "https://example.com", token: String(repeating: "a", count: 43))
        #expect(throws: ProtocolError.self) { try ready.validated(expectedPID: 1) }
}

@Test func parsesFragmentedSSEAndIgnoresComment() throws {
        var parser = SSEParser()
        #expect(try parser.ingest(Data(": keepalive\n\nid: 3\nevent: message_completed\ndata: {\"id\":3".utf8)).isEmpty)
        let frames = try parser.ingest(Data(",\"session_id\":\"s\",\"schema_version\":1,\"occurred_at\":\"now\",\"type\":\"message_completed\",\"data\":{}}\n\n".utf8))
        #expect(frames.count == 1)
        #expect(frames[0].id == "3")
        #expect(frames[0].event == "message_completed")
}

@Test func preservesUnknownEventTypeAndMultilinePayload() throws {
        var parser = SSEParser()
        let frames = try parser.ingest(Data("id: 9\nevent: future_event\ndata: {\"id\":9,\"session_id\":\"s\",\ndata: \"schema_version\":1,\"occurred_at\":\"now\",\"type\":\"future_event\",\"data\":{\"next\":true}}\n\n".utf8))
        #expect(frames.count == 1)
        let event = try JSONDecoder().decode(PiqoEvent.self, from: Data(frames[0].data.utf8))
        guard case .unknown(let type, let data) = event.kind else { Issue.record("Expected unknown event"); return }
        #expect(type == "future_event")
        #expect(data.objectValue?["next"]?.boolValue == true)
}
