import Testing
@testable import PiqoRuntime

@Test func diagnosticBufferRedactsAnnouncedToken() async {
        let buffer = DiagnosticBuffer(capacity: 2)
        await buffer.append("token abc", token: "abc")
        let snapshot = await buffer.snapshot()
        #expect(snapshot == ["token [REDACTED]"])
}
