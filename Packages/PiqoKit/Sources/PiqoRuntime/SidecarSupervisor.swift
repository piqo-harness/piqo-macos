import Foundation
import Observation
import PiqoProtocol

public enum SidecarState: Sendable, Equatable {
    case stopped, starting, ready, stopping, offline(String), failed(String)
}

public actor DiagnosticBuffer {
    private var lines: [String] = []
    private let capacity: Int
    public init(capacity: Int = 2_000) { self.capacity = capacity }
    public func append(_ line: String, token: String? = nil) {
        let redacted = token.map { line.replacingOccurrences(of: $0, with: "[REDACTED]") } ?? line
        lines.append(redacted)
        if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
    }
    public func snapshot() -> [String] { lines }
}

public actor SidecarSupervisor {
    public private(set) var state: SidecarState = .stopped
    public private(set) var client: PiqoAPIClient?
    public let diagnostics = DiagnosticBuffer()
    private var process: Process?
    private var sidecar: ValidatedSidecar?
    private var restartAttempts = 0
    private var stableSince: Date?
    private var executableURL: URL?

    public init() {}

    public func start(executableURL: URL) async throws -> PiqoAPIClient {
        if let client, case .ready = state { return client }
        state = .starting
        self.executableURL = executableURL
        let process = Process(); process.executableURL = executableURL
        let output = Pipe(); let error = Pipe()
        process.standardOutput = output; process.standardError = error
        error.fileHandleForReading.readabilityHandler = { [diagnostics] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { await diagnostics.append(text) }
        }
        do { try process.run() } catch { state = .failed(error.localizedDescription); throw error }
        self.process = process
        do {
            let line = try await firstLine(from: output.fileHandleForReading, timeout: .seconds(15))
            switch try StartupMessage.parse(line) {
            case .fatal(let fatal):
                state = .failed(fatal.code)
                process.terminate()
                throw SidecarFailure.fatal(code: fatal.code, message: fatal.message)
            case .ready(let ready):
                let validated = try ready.validated(expectedPID: process.processIdentifier)
                let api = PiqoAPIClient(sidecar: validated)
                try await verifyHealth(api)
                sidecar = validated; client = api; state = .ready; stableSince = Date()
                observeTermination(process)
                return api
            }
        } catch {
            if process.isRunning { process.terminate() }
            if case .failed = state {} else { state = .failed(error.localizedDescription) }
            throw error
        }
    }

    public func stop(gracefullyWithin timeout: Duration = .seconds(12)) async {
        guard let process else { state = .stopped; return }
        state = .stopping
        process.terminate()
        let deadline = ContinuousClock.now + timeout
        while process.isRunning, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(100)) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        self.process = nil; sidecar = nil; client = nil; state = .stopped
    }

    public func recover(executableURL: URL) async {
        guard restartAttempts < 3 else { state = .offline("The sidecar repeatedly stopped. Repair settings or restart Piqo."); return }
        restartAttempts += 1
        try? await Task.sleep(for: .milliseconds(500 * Int64(1 << (restartAttempts - 1))))
        do { _ = try await start(executableURL: executableURL) } catch {
            if restartAttempts >= 3 { state = .offline("The sidecar repeatedly stopped. Repair settings or restart Piqo.") }
        }
    }

    private func verifyHealth(_ api: PiqoAPIClient) async throws {
        var lastError: Error?
        for delay in [0, 100, 250, 500, 1_000] {
            if delay > 0 { try await Task.sleep(for: .milliseconds(delay)) }
            do { _ = try await api.health(); return } catch { lastError = error }
        }
        throw lastError ?? PiqoAPIError.incompatibleHealth
    }

    private func observeTermination(_ process: Process) {
        process.terminationHandler = { [weak self] _ in
            Task { await self?.unexpectedTermination() }
        }
    }
    private func unexpectedTermination() async {
        if case .stopping = state { return }
        client = nil; sidecar = nil; process = nil
        if let stableSince, Date().timeIntervalSince(stableSince) > 60 { restartAttempts = 0 }
        state = .failed("The sidecar stopped unexpectedly.")
        if let executableURL { await recover(executableURL: executableURL) }
    }
}

public enum SidecarFailure: LocalizedError, Sendable, Equatable { case fatal(code: String, message: String); public var errorDescription: String? { if case .fatal(_, let message) = self { message } else { nil } } }

private func firstLine(from handle: FileHandle, timeout: Duration) async throws -> Data {
    let chunks = AsyncStream<Data> { continuation in
        handle.readabilityHandler = { file in
            let data = file.availableData
            if data.isEmpty {
                continuation.finish()
            } else {
                continuation.yield(data)
            }
        }
        continuation.onTermination = { _ in handle.readabilityHandler = nil }
    }
    return try await withThrowingTaskGroup(of: Data.self) { group in
        group.addTask {
            var result = Data()
            for await chunk in chunks {
                result.append(chunk)
                if let newline = result.firstIndex(of: 0x0A) { return result.prefix(upTo: newline) }
                if result.count > 64 * 1_024 { throw ProtocolError.malformedStartup }
            }
            throw ProtocolError.malformedStartup
        }
        group.addTask { try await Task.sleep(for: timeout); throw CancellationError() }
        let value = try await group.next()!
        group.cancelAll()
        handle.readabilityHandler = nil
        return value
    }
}
