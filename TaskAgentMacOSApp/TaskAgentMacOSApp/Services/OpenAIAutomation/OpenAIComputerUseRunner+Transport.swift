import Foundation

extension OpenAIComputerUseRunner {
    func sendResponsesRequest(
        model: String,
        input: [[String: Any]],
        tools: [[String: Any]],
        previousResponseId: String?,
        apiKey: String
    ) async throws -> OpenAIResponsesResponse {
        var requestBody: [String: Any] = [
            "model": model,
            "input": input,
            "tools": tools,
            "tool_choice": "auto",
            "truncation": "auto"
        ]
        if let previousResponseId, !previousResponseId.isEmpty {
            requestBody["previous_response_id"] = previousResponseId
        }

        let encodedRequest: Data
        do {
            encodedRequest = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw OpenAIExecutionPlannerError.invalidResponse
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = encodedRequest

        let bytesSent = request.httpBody?.count
        let urlString = request.url?.absoluteString ?? "unknown"

        let pair: (data: Data, response: URLResponse, attempt: Int, attemptStartedAt: Date)
        let response: HTTPURLResponse
        let data: Data
        let attempt: Int
        let attemptStartedAt: Date
        do {
            pair = try await dataWithRetry(for: request)
            guard let http = pair.response as? HTTPURLResponse else {
                recordCall(
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
            if isCancellation(error) {
                throw CancellationError()
            }
            throw OpenAIExecutionPlannerError.requestFailed(describeTransportError(error))
        }

        let requestID = headerValue(response, name: "x-request-id")
        guard (200..<300).contains(response.statusCode) else {
            let parsedError = try? jsonDecoder.decode(OpenAIErrorEnvelope.self, from: data)
            let message = serverMessage(from: data, statusCode: response.statusCode)
            recordCall(
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
            if let issue = classifyOpenAIUserFacingIssue(
                statusCode: response.statusCode,
                payload: parsedError?.error,
                requestID: requestID
            ) {
                throw OpenAIExecutionPlannerError.userFacingIssue(issue)
            }
            throw OpenAIExecutionPlannerError.requestFailed(message)
        }

        guard let payload = try? jsonDecoder.decode(OpenAIResponsesResponse.self, from: data) else {
            recordCall(
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
            throw OpenAIExecutionPlannerError.invalidToolLoopResponse
        }

        recordCall(
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

    func renderPrompt(_ template: String, taskMarkdown: String, screenWidth: Int, screenHeight: Int) -> String {
        template
            .replacingOccurrences(of: "{{OS_VERSION}}", with: ProcessInfo.processInfo.operatingSystemVersionString)
            .replacingOccurrences(of: "{{SCREEN_WIDTH}}", with: String(screenWidth))
            .replacingOccurrences(of: "{{SCREEN_HEIGHT}}", with: String(screenHeight))
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
