import Foundation

protocol OpenAIResponsesWebSocketConnecting {
    func connect(url: URL, apiKey: String) async throws -> any OpenAIResponsesWebSocket
}

protocol OpenAIResponsesWebSocket {
    func send(text: String) async throws
    func receive() async throws -> String
    func close(code: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

final class URLSessionOpenAIResponsesWebSocketConnector: OpenAIResponsesWebSocketConnecting {
    private let sessionFactory: @Sendable () -> URLSession

    init(sessionFactory: @escaping @Sendable () -> URLSession) {
        self.sessionFactory = sessionFactory
    }

    func connect(url: URL, apiKey: String) async throws -> any OpenAIResponsesWebSocket {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let session = sessionFactory()
        let task = session.webSocketTask(with: request)
        task.resume()
        return URLSessionOpenAIResponsesWebSocket(session: session, task: task)
    }
}

final class URLSessionOpenAIResponsesWebSocket: OpenAIResponsesWebSocket {
    private let session: URLSession
    private let task: URLSessionWebSocketTask

    init(session: URLSession, task: URLSessionWebSocketTask) {
        self.session = session
        self.task = task
    }

    func send(text: String) async throws {
        try await task.send(.string(text))
    }

    func receive() async throws -> String {
        let message = try await task.receive()
        switch message {
        case .string(let text):
            return text
        case .data(let data):
            guard let text = String(data: data, encoding: .utf8) else {
                throw OpenAIExecutionPlannerError.invalidResponse
            }
            return text
        @unknown default:
            throw OpenAIExecutionPlannerError.invalidResponse
        }
    }

    func close(code: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        task.cancel(with: code, reason: reason)
        session.invalidateAndCancel()
    }
}

protocol OpenAIResponsesTransportSession: AnyObject {
    func send(_ request: OpenAIResponsesTransportRequest) async throws -> OpenAIResponsesResponse
    func finish()
}

private enum OpenAIResponsesTransportFallbackError: Error {
    case fallbackToHTTP(String)
}

private final class OpenAIResponsesTransportController: OpenAIResponsesTransportSession {
    private unowned let runner: OpenAIComputerUseRunner
    private let mode: OpenAIResponsesTransportMode
    private let httpTransport: OpenAIHTTPResponsesTransportSession
    private let webSocketTransport: OpenAIWebSocketResponsesTransportSession
    private var usingHTTPFallback = false

    init(runner: OpenAIComputerUseRunner) {
        self.runner = runner
        self.mode = runner.transportMode
        self.httpTransport = OpenAIHTTPResponsesTransportSession(runner: runner)
        self.webSocketTransport = OpenAIWebSocketResponsesTransportSession(
            runner: runner,
            connector: runner.webSocketConnector
        )
    }

    func send(_ request: OpenAIResponsesTransportRequest) async throws -> OpenAIResponsesResponse {
        switch mode {
        case .http:
            return try await httpTransport.send(request)
        case .webSocketOnly:
            return try await webSocketTransport.send(request)
        case .webSocketPreferred:
            if usingHTTPFallback {
                return try await httpTransport.send(request)
            }

            do {
                return try await webSocketTransport.send(request)
            } catch let error as OpenAIResponsesTransportFallbackError {
                usingHTTPFallback = true
                let reason: String
                switch error {
                case .fallbackToHTTP(let message):
                    reason = message
                }
                runner.recordTrace(
                    kind: .info,
                    "Responses WebSocket transport falling back to HTTP for the remainder of this run: \(reason)"
                )
                webSocketTransport.finish()
                return try await httpTransport.send(request)
            }
        }
    }

    func finish() {
        webSocketTransport.finish()
        httpTransport.finish()
    }
}

private final class OpenAIHTTPResponsesTransportSession: OpenAIResponsesTransportSession {
    private unowned let runner: OpenAIComputerUseRunner

    init(runner: OpenAIComputerUseRunner) {
        self.runner = runner
    }

    func send(_ transportRequest: OpenAIResponsesTransportRequest) async throws -> OpenAIResponsesResponse {
        let encodedRequest: Data
        do {
            encodedRequest = try transportRequest.encodedResponseCreateBody()
        } catch {
            throw OpenAIExecutionPlannerError.invalidResponse
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(transportRequest.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = encodedRequest

        let bytesSent = request.httpBody?.count
        let urlString = request.url?.absoluteString ?? "unknown"

        let pair: (data: Data, response: URLResponse, attempt: Int, attemptStartedAt: Date)
        let response: HTTPURLResponse
        let data: Data
        let attempt: Int
        let attemptStartedAt: Date
        do {
            pair = try await runner.dataWithRetry(for: request)
            guard let http = pair.response as? HTTPURLResponse else {
                runner.recordCall(
                    startedAt: pair.attemptStartedAt,
                    finishedAt: Date(),
                    attempt: pair.attempt,
                    url: urlString,
                    httpStatus: nil,
                    requestId: nil,
                    bytesSent: bytesSent,
                    bytesReceived: pair.data.count,
                    outcome: .failure,
                    message: "Non-HTTP response."
                )
                throw OpenAIExecutionPlannerError.invalidResponse
            }
            response = http
            data = pair.data
            attempt = pair.attempt
            attemptStartedAt = pair.attemptStartedAt
        } catch let error as OpenAIExecutionPlannerError {
            throw error
        } catch {
            if runner.isCancellation(error) {
                throw CancellationError()
            }
            throw OpenAIExecutionPlannerError.requestFailed(runner.describeTransportError(error))
        }

        let requestID = runner.headerValue(response, name: "x-request-id")
        guard (200..<300).contains(response.statusCode) else {
            let parsedError = try? runner.jsonDecoder.decode(OpenAIErrorEnvelope.self, from: data)
            let message = runner.serverMessage(from: data, statusCode: response.statusCode)
            runner.recordExchange(
                startedAt: attemptStartedAt,
                finishedAt: Date(),
                attempt: attempt,
                url: urlString,
                httpStatus: response.statusCode,
                requestId: requestID,
                outcome: .failure,
                requestBodyData: encodedRequest,
                responseBodyData: data
            )
            runner.recordCall(
                startedAt: attemptStartedAt,
                finishedAt: Date(),
                attempt: attempt,
                url: urlString,
                httpStatus: response.statusCode,
                requestId: requestID,
                bytesSent: bytesSent,
                bytesReceived: data.count,
                outcome: .failure,
                message: message
            )
            if let issue = runner.classifyOpenAIUserFacingIssue(
                statusCode: response.statusCode,
                payload: parsedError?.error,
                requestID: requestID
            ) {
                throw OpenAIExecutionPlannerError.userFacingIssue(issue)
            }
            throw OpenAIExecutionPlannerError.requestFailed(message)
        }

        guard let payload = try? runner.jsonDecoder.decode(OpenAIResponsesResponse.self, from: data) else {
            runner.recordExchange(
                startedAt: attemptStartedAt,
                finishedAt: Date(),
                attempt: attempt,
                url: urlString,
                httpStatus: response.statusCode,
                requestId: requestID,
                outcome: .failure,
                requestBodyData: encodedRequest,
                responseBodyData: data
            )
            runner.recordCall(
                startedAt: attemptStartedAt,
                finishedAt: Date(),
                attempt: attempt,
                url: urlString,
                httpStatus: response.statusCode,
                requestId: requestID,
                bytesSent: bytesSent,
                bytesReceived: data.count,
                outcome: .failure,
                message: "Failed to decode OpenAI response JSON."
            )
            throw OpenAIExecutionPlannerError.invalidResponse
        }

        let hasOutputItems = !(payload.output ?? []).isEmpty
        let hasOutputText = !(payload.outputText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        guard hasOutputItems || hasOutputText else {
            runner.recordExchange(
                startedAt: attemptStartedAt,
                finishedAt: Date(),
                attempt: attempt,
                url: urlString,
                httpStatus: response.statusCode,
                requestId: requestID,
                outcome: .failure,
                requestBodyData: encodedRequest,
                responseBodyData: data
            )
            throw OpenAIExecutionPlannerError.invalidToolLoopResponse
        }

        runner.recordExchange(
            startedAt: attemptStartedAt,
            finishedAt: Date(),
            attempt: attempt,
            url: urlString,
            httpStatus: response.statusCode,
            requestId: requestID,
            outcome: .success,
            requestBodyData: encodedRequest,
            responseBodyData: data
        )
        runner.recordCall(
            startedAt: attemptStartedAt,
            finishedAt: Date(),
            attempt: attempt,
            url: urlString,
            httpStatus: response.statusCode,
            requestId: requestID,
            bytesSent: bytesSent,
            bytesReceived: data.count,
            outcome: .success,
            message: nil
        )
        return payload
    }

    func finish() {}
}

private final class OpenAIWebSocketResponsesTransportSession: OpenAIResponsesTransportSession {
    private let url = URL(string: "wss://api.openai.com/v1/responses")!
    private unowned let runner: OpenAIComputerUseRunner
    private let connector: any OpenAIResponsesWebSocketConnecting
    private var socket: (any OpenAIResponsesWebSocket)?

    init(
        runner: OpenAIComputerUseRunner,
        connector: any OpenAIResponsesWebSocketConnecting
    ) {
        self.runner = runner
        self.connector = connector
    }

    func send(_ request: OpenAIResponsesTransportRequest) async throws -> OpenAIResponsesResponse {
        let encodedRequest: Data
        let encodedText: String
        do {
            encodedRequest = try request.encodedWebSocketEvent()
            guard let text = String(data: encodedRequest, encoding: .utf8) else {
                throw OpenAIExecutionPlannerError.invalidResponse
            }
            encodedText = text
        } catch let error as OpenAIExecutionPlannerError {
            throw error
        } catch {
            throw OpenAIExecutionPlannerError.invalidResponse
        }

        let urlString = url.absoluteString

        for attempt in 1...2 {
            let startedAt = Date()
            let bytesSent = encodedRequest.count
            var bytesReceived = 0
            let accumulator = OpenAIResponsesWebSocketAccumulator()
            let hadActiveSocketAtTurnStart = socket != nil

            do {
                let socket = try await ensureConnected(apiKey: request.apiKey)
                try await socket.send(text: encodedText)

                while true {
                    let messageText = try await socket.receive()
                    bytesReceived += messageText.utf8.count
                    guard let data = messageText.data(using: .utf8) else {
                        throw OpenAIExecutionPlannerError.invalidResponse
                    }
                    let event = try runner.jsonDecoder.decode(OpenAIResponsesWebSocketEvent.self, from: data)
                    if let requestID = event.requestID?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !requestID.isEmpty {
                        accumulator.requestID = requestID
                    }

                    if event.type == "error" {
                        let requestID = accumulator.requestID
                        let message = event.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "WebSocket error"
                        let responseBodyData = try? runner.jsonEncoder.encode(
                            OpenAIErrorEnvelope(error: event.error)
                        )

                        runner.recordExchange(
                            startedAt: startedAt,
                            finishedAt: Date(),
                            attempt: attempt,
                            url: urlString,
                            httpStatus: event.status,
                            requestId: requestID,
                            outcome: .failure,
                            requestBodyData: encodedRequest,
                            responseBodyData: responseBodyData
                        )
                        runner.recordCall(
                            startedAt: startedAt,
                            finishedAt: Date(),
                            attempt: attempt,
                            url: urlString,
                            httpStatus: event.status,
                            requestId: requestID,
                            bytesSent: bytesSent,
                            bytesReceived: bytesReceived,
                            outcome: .failure,
                            message: message
                        )

                        if event.error?.code == "websocket_connection_limit_reached", attempt < 2 {
                            runner.recordTrace(
                                kind: .info,
                                "Responses WebSocket transport reached the connection limit; reconnecting and retrying the turn."
                            )
                            closeSocket(reason: "connection_limit_reached")
                            break
                        }

                        if event.error?.code == "previous_response_not_found" {
                            closeSocket(reason: "previous_response_not_found")
                            throw OpenAIResponsesTransportFallbackError.fallbackToHTTP(message)
                        }

                        if let issue = runner.classifyOpenAIUserFacingIssue(
                            statusCode: event.status ?? 400,
                            payload: event.error,
                            requestID: requestID
                        ) {
                            throw OpenAIExecutionPlannerError.userFacingIssue(issue)
                        }

                        throw OpenAIExecutionPlannerError.requestFailed(message)
                    }

                    if let payload = accumulator.apply(event) {
                        let normalizedData = try runner.jsonEncoder.encode(payload)
                        let hasOutputItems = !(payload.output ?? []).isEmpty
                        let hasOutputText = !(payload.outputText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                        guard hasOutputItems || hasOutputText else {
                            runner.recordExchange(
                                startedAt: startedAt,
                                finishedAt: Date(),
                                attempt: attempt,
                                url: urlString,
                                httpStatus: nil,
                                requestId: accumulator.requestID,
                                outcome: .failure,
                                requestBodyData: encodedRequest,
                                responseBodyData: normalizedData
                            )
                            throw OpenAIExecutionPlannerError.invalidToolLoopResponse
                        }

                        runner.recordExchange(
                            startedAt: startedAt,
                            finishedAt: Date(),
                            attempt: attempt,
                            url: urlString,
                            httpStatus: nil,
                            requestId: accumulator.requestID,
                            outcome: .success,
                            requestBodyData: encodedRequest,
                            responseBodyData: normalizedData
                        )
                        runner.recordCall(
                            startedAt: startedAt,
                            finishedAt: Date(),
                            attempt: attempt,
                            url: urlString,
                            httpStatus: nil,
                            requestId: accumulator.requestID,
                            bytesSent: bytesSent,
                            bytesReceived: bytesReceived,
                            outcome: .success,
                            message: nil
                        )
                        return payload
                    }
                }
            } catch is CancellationError {
                closeSocket(reason: "cancelled")
                throw CancellationError()
            } catch let error as OpenAIResponsesTransportFallbackError {
                throw error
            } catch let error as OpenAIExecutionPlannerError {
                throw error
            } catch {
                let message = runner.describeTransportError(error)
                runner.recordExchange(
                    startedAt: startedAt,
                    finishedAt: Date(),
                    attempt: attempt,
                    url: urlString,
                    httpStatus: nil,
                    requestId: accumulator.requestID,
                    outcome: .failure,
                    requestBodyData: encodedRequest,
                    responseBodyData: nil
                )
                runner.recordCall(
                    startedAt: startedAt,
                    finishedAt: Date(),
                    attempt: attempt,
                    url: urlString,
                    httpStatus: nil,
                    requestId: accumulator.requestID,
                    bytesSent: bytesSent,
                    bytesReceived: bytesReceived,
                    outcome: .failure,
                    message: message
                )

                if attempt < 2,
                   hadActiveSocketAtTurnStart,
                   runner.shouldReconnectWebSocketAfterTransportError(error) {
                    runner.recordTrace(
                        kind: .info,
                        "Responses WebSocket transport hit a transient error; reconnecting and retrying the current turn."
                    )
                    closeSocket(reason: "transient_transport_error")
                    continue
                }

                closeSocket(reason: "transport_failure")
                throw OpenAIResponsesTransportFallbackError.fallbackToHTTP(message)
            }
        }

        throw OpenAIResponsesTransportFallbackError.fallbackToHTTP("Responses WebSocket transport could not complete the current turn.")
    }

    func finish() {
        closeSocket(reason: "run_finished")
    }

    private func ensureConnected(apiKey: String) async throws -> any OpenAIResponsesWebSocket {
        if let socket {
            runner.recordTrace(kind: .info, "Responses WebSocket transport reusing the active connection.")
            return socket
        }

        runner.recordTrace(kind: .info, "Responses WebSocket transport opening a new connection.")
        let socket = try await connector.connect(url: url, apiKey: apiKey)
        self.socket = socket
        return socket
    }

    private func closeSocket(reason: String) {
        guard let socket else { return }
        runner.recordTrace(kind: .info, "Responses WebSocket transport closing connection (\(reason)).")
        socket.close(code: .normalClosure, reason: Data(reason.utf8))
        self.socket = nil
    }
}

private final class OpenAIResponsesWebSocketAccumulator {
    var requestID: String?
    private var responseID: String?
    private var outputText = ""
    private var outputItemsByIndex: [Int: OpenAIResponseOutputItem] = [:]
    private var functionArgumentBuffers: [Int: String] = [:]

    func apply(_ event: OpenAIResponsesWebSocketEvent) -> OpenAIResponsesResponse? {
        mergeResponse(event.response)

        switch event.type {
        case "response.output_item.added", "response.output_item.done":
            if let item = event.item {
                store(item: item, index: event.outputIndex ?? nextOutputIndex())
            }
        case "response.function_call_arguments.delta":
            if let outputIndex = event.outputIndex, let delta = event.delta {
                functionArgumentBuffers[outputIndex, default: ""].append(delta)
                updateArgumentsForStoredItem(at: outputIndex)
            }
        case "response.function_call_arguments.done":
            if let outputIndex = event.outputIndex {
                if let arguments = event.arguments {
                    functionArgumentBuffers[outputIndex] = arguments
                }
                updateArgumentsForStoredItem(at: outputIndex)
            }
        case "response.output_text.delta":
            if let delta = event.delta {
                outputText.append(delta)
            }
        case "response.output_text.done":
            if let text = event.text, outputText.isEmpty {
                outputText = text
            }
        case "response.completed":
            return buildResponse()
        default:
            break
        }

        return nil
    }

    private func mergeResponse(_ response: OpenAIResponsesResponse?) {
        guard let response else { return }
        if let id = response.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            responseID = id
        }
        if let outputText = response.outputText, !outputText.isEmpty {
            self.outputText = outputText
        }
        if let output = response.output {
            for (index, item) in output.enumerated() {
                store(item: item, index: index)
            }
        }
    }

    private func nextOutputIndex() -> Int {
        (outputItemsByIndex.keys.max() ?? -1) + 1
    }

    private func store(item: OpenAIResponseOutputItem, index: Int) {
        var merged = item
        if let bufferedArguments = functionArgumentBuffers[index],
           merged.arguments == nil {
            merged.arguments = .string(bufferedArguments)
        }

        if let existing = outputItemsByIndex[index] {
            merged = OpenAIResponseOutputItem(
                type: merged.type.isEmpty ? existing.type : merged.type,
                id: merged.id ?? existing.id,
                callID: merged.callID ?? existing.callID,
                name: merged.name ?? existing.name,
                arguments: merged.arguments ?? existing.arguments,
                content: merged.content ?? existing.content,
                summary: merged.summary ?? existing.summary,
                text: merged.text ?? existing.text
            )
        }
        outputItemsByIndex[index] = merged
    }

    private func updateArgumentsForStoredItem(at index: Int) {
        guard var item = outputItemsByIndex[index],
              let bufferedArguments = functionArgumentBuffers[index] else {
            return
        }
        item.arguments = .string(bufferedArguments)
        outputItemsByIndex[index] = item
    }

    private func buildResponse() -> OpenAIResponsesResponse {
        let output: [OpenAIResponseOutputItem]?
        if outputItemsByIndex.isEmpty {
            output = nil
        } else {
            output = outputItemsByIndex.keys.sorted().compactMap { outputItemsByIndex[$0] }
        }

        return OpenAIResponsesResponse(
            id: responseID,
            output: output,
            outputText: outputText.isEmpty ? nil : outputText
        )
    }
}

extension OpenAIComputerUseRunner {
    func makeResponsesTransportSession() -> any OpenAIResponsesTransportSession {
        OpenAIResponsesTransportController(runner: self)
    }

    func dataWithRetry(for request: URLRequest) async throws -> (data: Data, response: URLResponse, attempt: Int, attemptStartedAt: Date) {
        let maxAttempts = max(1, transportRetryPolicy.maxAttempts)
        for attempt in 1...maxAttempts {
            let startedAt = Date()
            let session = sessionFactory()
            do {
                defer {
                    session.finishTasksAndInvalidate()
                }
                let pair = try await session.data(for: request)
                return (pair.0, pair.1, attempt, startedAt)
            } catch {
                if isCancellation(error) {
                    recordCall(
                        startedAt: startedAt,
                        finishedAt: Date(),
                        attempt: attempt,
                        url: request.url?.absoluteString ?? "unknown",
                        httpStatus: nil,
                        requestId: nil,
                        bytesSent: request.httpBody?.count,
                        bytesReceived: nil,
                        outcome: .failure,
                        message: "Cancelled."
                    )
                    throw CancellationError()
                }

                recordCall(
                    startedAt: startedAt,
                    finishedAt: Date(),
                    attempt: attempt,
                    url: request.url?.absoluteString ?? "unknown",
                    httpStatus: nil,
                    requestId: nil,
                    bytesSent: request.httpBody?.count,
                    bytesReceived: nil,
                    outcome: .failure,
                    message: describeTransportError(error)
                )

                if attempt < maxAttempts, shouldRetryTransportError(error) {
                    let delaySeconds = computeRetryDelaySeconds(attempt: attempt)
                    recordTrace(
                        kind: .info,
                        "Retrying OpenAI request after transport error (attempt \(attempt + 1)/\(maxAttempts)) after \(String(format: "%.2f", delaySeconds))s."
                    )
                    await sleepNanoseconds(UInt64(max(0.0, delaySeconds) * 1_000_000_000))
                    continue
                }
                throw error
            }
        }

        throw URLError(.unknown)
    }

    static func copySessionConfiguration(from configuration: URLSessionConfiguration) -> URLSessionConfiguration {
        if let copied = configuration.copy() as? URLSessionConfiguration {
            return copied
        }

        let fallback = URLSessionConfiguration.ephemeral
        fallback.timeoutIntervalForRequest = configuration.timeoutIntervalForRequest
        fallback.timeoutIntervalForResource = configuration.timeoutIntervalForResource
        fallback.httpAdditionalHeaders = configuration.httpAdditionalHeaders
        fallback.httpMaximumConnectionsPerHost = configuration.httpMaximumConnectionsPerHost
        fallback.waitsForConnectivity = configuration.waitsForConnectivity
        fallback.requestCachePolicy = configuration.requestCachePolicy
        fallback.urlCache = configuration.urlCache
        fallback.protocolClasses = configuration.protocolClasses
        return fallback
    }

    func computeRetryDelaySeconds(attempt: Int) -> Double {
        let base = max(0.0, transportRetryPolicy.baseDelaySeconds)
        let maxDelay = max(0.0, transportRetryPolicy.maxDelaySeconds)
        let exponent = max(0.0, Double(attempt - 1))
        let delay = base * pow(2.0, exponent)
        return min(delay, maxDelay)
    }

    func shouldRetryTransportError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return false
        }

        switch nsError.code {
        case URLError.secureConnectionFailed.rawValue,
             URLError.networkConnectionLost.rawValue,
             URLError.timedOut.rawValue,
             URLError.cannotConnectToHost.rawValue,
             URLError.cannotFindHost.rawValue,
             URLError.dnsLookupFailed.rawValue,
             URLError.notConnectedToInternet.rawValue:
            return true
        default:
            return false
        }
    }

    func shouldReconnectWebSocketAfterTransportError(_ error: Error) -> Bool {
        shouldRetryTransportError(error)
    }

    func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == URLError.cancelled.rawValue
    }

    func recordCall(
        startedAt: Date,
        finishedAt: Date,
        attempt: Int,
        url: String,
        httpStatus: Int?,
        requestId: String?,
        bytesSent: Int?,
        bytesReceived: Int?,
        outcome: LLMCallOutcome,
        message: String?
    ) {
        callLogSink?(
            LLMCallLogEntry(
                startedAt: startedAt,
                finishedAt: finishedAt,
                provider: .openAI,
                operation: .execution,
                attempt: attempt,
                url: url,
                httpStatus: httpStatus,
                requestId: requestId,
                bytesSent: bytesSent,
                bytesReceived: bytesReceived,
                outcome: outcome,
                message: message
            )
        )
    }

    func recordExchange(
        startedAt: Date,
        finishedAt: Date,
        attempt: Int,
        url: String,
        httpStatus: Int?,
        requestId: String?,
        outcome: LLMCallOutcome,
        requestBodyData: Data,
        responseBodyData: Data?
    ) {
        exchangeLogSink?(
            LLMExchangeLogEntry(
                startedAt: startedAt,
                finishedAt: finishedAt,
                provider: .openAI,
                operation: .execution,
                attempt: attempt,
                url: url,
                httpStatus: httpStatus,
                requestId: requestId,
                outcome: outcome,
                requestBodyData: requestBodyData,
                responseBodyData: responseBodyData
            )
        )
    }

    func headerValue(_ response: HTTPURLResponse, name: String) -> String? {
        for (keyAny, valueAny) in response.allHeaderFields {
            guard let key = keyAny as? String else { continue }
            if key.lowercased() == name.lowercased() {
                if let value = valueAny as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
                return "\(valueAny)"
            }
        }
        return nil
    }

    func describeTransportError(_ error: Error) -> String {
        let nsError = error as NSError
        var components: [String] = []

        components.append("\(nsError.localizedDescription) (domain=\(nsError.domain) code=\(nsError.code))")
        if let failingURL = (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL) {
            components.append("url=\(failingURL.absoluteString)")
        }

        var depth = 0
        var underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        while let underlyingError = underlying, depth < 3 {
            components.append(
                "underlying=\(underlyingError.localizedDescription) (domain=\(underlyingError.domain) code=\(underlyingError.code))"
            )
            underlying = underlyingError.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }

        if nsError.domain == NSURLErrorDomain, nsError.code == URLError.secureConnectionFailed.rawValue {
            components.append(
                "hint=TLS handshake failed (-1200). Common causes: VPN/proxy TLS inspection, captive portals, missing/blocked trust roots, or incorrect system clock."
            )
        }

        return components.joined(separator: " | ")
    }

    func resolveAPIKey() throws -> String {
        do {
            guard let raw = try apiKeyStore.readKey(for: .openAI) else {
                throw OpenAIExecutionPlannerError.missingAPIKey
            }
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                throw OpenAIExecutionPlannerError.missingAPIKey
            }
            return key
        } catch let error as OpenAIExecutionPlannerError {
            throw error
        } catch {
            throw OpenAIExecutionPlannerError.failedToReadAPIKey
        }
    }

    func loadPromptTemplate() throws -> PromptTemplate {
        do {
            return try promptCatalog.loadPrompt(named: promptName)
        } catch {
            throw OpenAIExecutionPlannerError.failedToLoadPrompt(promptName)
        }
    }

    func renderPrompt(_ template: String, taskMarkdown: String, screenshot: OpenAICapturedScreenshot) -> String {
        template
            .replacingOccurrences(of: "{{OS_VERSION}}", with: ProcessInfo.processInfo.operatingSystemVersionString)
            .replacingOccurrences(of: "{{SCREEN_WIDTH}}", with: String(screenshot.width))
            .replacingOccurrences(of: "{{SCREEN_HEIGHT}}", with: String(screenshot.height))
            .replacingOccurrences(of: "{{TASK_MARKDOWN}}", with: taskMarkdown)
    }

    func serverMessage(from data: Data, statusCode: Int) -> String {
        if let payload = try? jsonDecoder.decode(OpenAIErrorEnvelope.self, from: data),
           let message = payload.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return message
        }
        return "HTTP \(statusCode)"
    }

    func classifyOpenAIUserFacingIssue(
        statusCode: Int,
        payload: OpenAIErrorEnvelope.Payload?,
        requestID: String?
    ) -> LLMUserFacingIssue? {
        let rawMessage = payload?.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "HTTP \(statusCode)"
        let providerCode = payload?.code?.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerType = payload?.type?.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = [
            rawMessage.lowercased(),
            providerCode?.lowercased() ?? "",
            providerType?.lowercased() ?? ""
        ].joined(separator: " ")

        let kind: LLMUserFacingIssueKind?
        if statusCode == 401 || combined.contains("invalid_api_key") || combined.contains("incorrect api key") {
            kind = .invalidCredentials
        } else if statusCode == 429 {
            if containsAnyToken(
                combined,
                tokens: ["insufficient_quota", "quota", "budget", "billing_hard_limit", "exceeded your current quota", "usage limit"]
            ) {
                kind = .quotaOrBudgetExhausted
            } else {
                kind = .rateLimited
            }
        } else if (statusCode == 400 || statusCode == 403) &&
            containsAnyToken(combined, tokens: ["billing", "tier", "payment", "not enabled", "verification"]) {
            kind = .billingOrTierNotEnabled
        } else {
            kind = nil
        }

        guard let kind else {
            return nil
        }
        return LLMUserFacingIssue(
            provider: .openAI,
            operation: .execution,
            kind: kind,
            providerMessage: rawMessage,
            httpStatus: statusCode,
            providerCode: providerCode?.isEmpty == true ? nil : providerCode,
            requestID: requestID
        )
    }

    func containsAnyToken(_ text: String, tokens: [String]) -> Bool {
        for token in tokens where text.contains(token.lowercased()) {
            return true
        }
        return false
    }
}
