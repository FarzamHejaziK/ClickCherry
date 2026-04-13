import Foundation

actor MCPJSONRPCClient {
    private let transport: MCPStdioTransport
    private let requestTimeout: TimeInterval
    private var nextRequestID = 1
    private var pendingRequests: [Int: CheckedContinuation<MCPValue, Error>] = [:]
    private var disconnectReason: String?
    private var diagnostics: [String] = []

    init(transport: MCPStdioTransport, requestTimeout: TimeInterval) {
        self.transport = transport
        self.requestTimeout = requestTimeout
    }

    func installTransportHandlers() {
        transport.onMessage = { [weak self] data in
            Task { await self?.handleIncomingMessage(data) }
        }
        transport.onDisconnect = { [weak self] reason in
            Task { await self?.handleDisconnect(reason: reason) }
        }
        transport.onStderr = { [weak self] text in
            Task { await self?.recordDiagnostic(text) }
        }
    }

    func request(method: String, params: MCPValue?) async throws -> MCPValue {
        if let disconnectReason {
            throw MCPRuntimeError.serverDisconnected(disconnectReason)
        }

        let requestID = nextRequestID
        nextRequestID += 1

        let envelope = MCPJSONRPCRequestEnvelope(id: requestID, method: method, params: params)
        let payload = try JSONEncoder().encode(envelope)

        let timeoutTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(requestTimeout * 1_000_000_000))
            await self.failPendingRequest(
                requestID,
                error: MCPRuntimeError.requestTimedOut(method: method, seconds: requestTimeout)
            )
        }

        defer { timeoutTask.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestID] = continuation
            do {
                try transport.send(payload)
            } catch {
                pendingRequests.removeValue(forKey: requestID)
                continuation.resume(throwing: error)
            }
        }
    }

    func notify(method: String, params: MCPValue?) async throws {
        if let disconnectReason {
            throw MCPRuntimeError.serverDisconnected(disconnectReason)
        }

        let envelope = MCPJSONRPCNotificationEnvelope(method: method, params: params)
        let payload = try JSONEncoder().encode(envelope)
        try transport.send(payload)
    }

    func currentDiagnostics() -> [String] {
        diagnostics
    }

    func isDisconnected() -> Bool {
        disconnectReason != nil
    }

    private func handleIncomingMessage(_ data: Data) {
        do {
            let response = try JSONDecoder().decode(MCPJSONRPCResponseEnvelope.self, from: data)
            guard let requestID = response.id?.intValue else { return }

            if let error = response.error {
                failPendingRequest(requestID, error: error)
                return
            }

            if let result = response.result {
                resolvePendingRequest(requestID, value: result)
            } else {
                failPendingRequest(requestID, error: MCPRuntimeError.invalidResponse("Missing result payload."))
            }
        } catch {
            diagnostics.append("Failed to decode MCP message: \(error.localizedDescription)")
        }
    }

    private func handleDisconnect(reason: String) {
        disconnectReason = reason
        let pending = pendingRequests
        pendingRequests.removeAll()
        for continuation in pending.values {
            continuation.resume(throwing: MCPRuntimeError.serverDisconnected(reason))
        }
    }

    private func recordDiagnostic(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        diagnostics.append(trimmed)
    }

    private func resolvePendingRequest(_ requestID: Int, value: MCPValue) {
        guard let continuation = pendingRequests.removeValue(forKey: requestID) else { return }
        continuation.resume(returning: value)
    }

    private func failPendingRequest(_ requestID: Int, error: Error) {
        guard let continuation = pendingRequests.removeValue(forKey: requestID) else { return }
        continuation.resume(throwing: error)
    }
}
