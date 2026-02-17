import Foundation
import Testing
@testable import TaskAgentMacOSApp

private final class StubAPIKeyStore: APIKeyStore {
    private var values: [ProviderIdentifier: String]
    private var shouldThrowOnRead: Bool

    init(values: [ProviderIdentifier: String] = [:], shouldThrowOnRead: Bool = false) {
        self.values = values
        self.shouldThrowOnRead = shouldThrowOnRead
    }

    func hasKey(for provider: ProviderIdentifier) -> Bool {
        guard let value = values[provider] else {
            return false
        }
        return !value.isEmpty
    }

    func readKey(for provider: ProviderIdentifier) throws -> String? {
        if shouldThrowOnRead {
            throw KeychainStoreError.unhandledStatus(-1)
        }
        return values[provider]
    }

    func setKey(_ key: String?, for provider: ProviderIdentifier) throws {
        values[provider] = key
    }
}

private final class QueueURLProtocol: URLProtocol {
    static let lock = NSLock()
    static var handlers: [((URLRequest) throws -> (HTTPURLResponse, Data))] = []
    static var capturedRequests: [URLRequest] = []

    static func reset() {
        lock.lock()
        handlers = []
        capturedRequests = []
        lock.unlock()
    }

    static func enqueue(_ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock()
        handlers.append(handler)
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        QueueURLProtocol.lock.lock()
        QueueURLProtocol.capturedRequests.append(request)
        let handler = QueueURLProtocol.handlers.isEmpty ? nil : QueueURLProtocol.handlers.removeFirst()
        QueueURLProtocol.lock.unlock()

        guard let handler else {
            let error = NSError(
                domain: "QueueURLProtocol",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No stubbed handler available."]
            )
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite(.serialized)
@MainActor
struct GeminiVideoLLMClientTests {
    @Test
    func analyzeVideoFailsWhenGeminiKeyMissing() async throws {
        let session = makeSession()
        let client = GeminiVideoLLMClient(
            apiKeyStore: StubAPIKeyStore(),
            session: session,
            pollIntervalNanoseconds: 1,
            maxPollAttempts: 1
        )

        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let videoURL = tempRoot.appendingPathComponent("sample.mp4", isDirectory: false)
        try Data("video".utf8).write(to: videoURL)

        do {
            _ = try await client.analyzeVideo(at: videoURL, prompt: "Prompt", model: "gemini-3-pro")
            #expect(Bool(false))
        } catch let error as GeminiLLMClientError {
            #expect(error == .missingAPIKey)
        }
    }

    @Test
    func analyzeVideoUploadsPollsAndGeneratesExtractionOutput() async throws {
        QueueURLProtocol.reset()
        let session = makeSession()

        let uploadSessionURL = URL(string: "https://upload.example/session-1")!
        QueueURLProtocol.enqueue { request in
            let response = Self.httpResponse(
                url: request.url!,
                statusCode: 200,
                headers: ["X-Goog-Upload-URL": uploadSessionURL.absoluteString]
            )
            return (response, Data())
        }
        QueueURLProtocol.enqueue { request in
            let body = """
            {"file":{"name":"files/mock-video","uri":"https://files.example/mock-video","state":"PROCESSING"}}
            """
            let response = Self.httpResponse(url: request.url!, statusCode: 200)
            return (response, Data(body.utf8))
        }
        QueueURLProtocol.enqueue { request in
            let body = """
            {"name":"files/mock-video","uri":"https://files.example/mock-video","state":"ACTIVE"}
            """
            let response = Self.httpResponse(url: request.url!, statusCode: 200)
            return (response, Data(body.utf8))
        }
        QueueURLProtocol.enqueue { request in
            let body = """
            {"candidates":[{"content":{"parts":[{"text":"# Task\\nTaskDetected: true\\nStatus: TASK_FOUND\\nNoTaskReason: NONE\\nTitle: Submit expenses\\nGoal: Submit monthly expenses\\nAppsObserved:\\n- Browser\\n\\n## Questions\\n- None."}]}}]}
            """
            let response = Self.httpResponse(url: request.url!, statusCode: 200)
            return (response, Data(body.utf8))
        }

        let client = GeminiVideoLLMClient(
            apiKeyStore: StubAPIKeyStore(values: [.gemini: "gemini-key-123"]),
            session: session,
            pollIntervalNanoseconds: 1,
            maxPollAttempts: 3
        )

        let tempRoot = try makeTempRoot()
        defer {
            QueueURLProtocol.reset()
            try? FileManager.default.removeItem(at: tempRoot)
        }
        let videoURL = tempRoot.appendingPathComponent("sample.mp4", isDirectory: false)
        try Data("video".utf8).write(to: videoURL)

        let result = try await client.analyzeVideo(
            at: videoURL,
            prompt: "Extract the task from this video.",
            model: "gemini-3-pro"
        )

        #expect(result.contains("# Task"))
        #expect(result.contains("TaskDetected: true"))
        let capturedRequests = QueueURLProtocol.capturedRequests
        #expect(capturedRequests.count == 4)

        let uploadStartRequest = capturedRequests[0]
        #expect(uploadStartRequest.url?.path == "/upload/v1beta/files")
        #expect(uploadStartRequest.value(forHTTPHeaderField: "X-Goog-Upload-Protocol") == "resumable")
        #expect(uploadStartRequest.value(forHTTPHeaderField: "X-Goog-Upload-Command") == "start")

        let uploadBodyRequest = capturedRequests[1]
        #expect(uploadBodyRequest.url == uploadSessionURL)
        #expect(uploadBodyRequest.value(forHTTPHeaderField: "X-Goog-Upload-Command") == "upload, finalize")

        let pollRequest = capturedRequests[2]
        #expect(pollRequest.url?.path == "/v1beta/files/mock-video")

        let generateRequest = capturedRequests[3]
        #expect(generateRequest.url?.path == "/v1beta/models/gemini-3-pro-preview:generateContent")
        #expect(Self.requestBodyString(from: generateRequest)?.contains("Extract the task from this video.") == true)
        #expect(Self.requestIncludesFileURI(generateRequest, expectedURI: "https://files.example/mock-video"))
    }

    @Test
    func analyzeVideoReturnsServerMessageWhenGenerateFails() async throws {
        QueueURLProtocol.reset()
        let session = makeSession()

        let uploadSessionURL = URL(string: "https://upload.example/session-2")!
        QueueURLProtocol.enqueue { request in
            let response = Self.httpResponse(
                url: request.url!,
                statusCode: 200,
                headers: ["X-Goog-Upload-URL": uploadSessionURL.absoluteString]
            )
            return (response, Data())
        }
        QueueURLProtocol.enqueue { request in
            let body = """
            {"file":{"name":"files/mock-video","uri":"https://files.example/mock-video","state":"ACTIVE"}}
            """
            let response = Self.httpResponse(url: request.url!, statusCode: 200)
            return (response, Data(body.utf8))
        }
        QueueURLProtocol.enqueue { request in
            let body = """
            {"error":{"code":400,"message":"Unknown model id","status":"INVALID_ARGUMENT"}}
            """
            let response = Self.httpResponse(url: request.url!, statusCode: 400)
            return (response, Data(body.utf8))
        }

        let client = GeminiVideoLLMClient(
            apiKeyStore: StubAPIKeyStore(values: [.gemini: "gemini-key-123"]),
            session: session,
            pollIntervalNanoseconds: 1,
            maxPollAttempts: 1
        )

        let tempRoot = try makeTempRoot()
        defer {
            QueueURLProtocol.reset()
            try? FileManager.default.removeItem(at: tempRoot)
        }
        let videoURL = tempRoot.appendingPathComponent("sample.mp4", isDirectory: false)
        try Data("video".utf8).write(to: videoURL)

        do {
            _ = try await client.analyzeVideo(
                at: videoURL,
                prompt: "Prompt",
                model: "gemini-3-pro-preview"
            )
            #expect(Bool(false))
        } catch let error as GeminiLLMClientError {
            guard case .generateFailed(let reason) = error else {
                #expect(Bool(false))
                return
            }
            #expect(reason == "Unknown model id")
        }
    }

    private static func httpResponse(
        url: URL,
        statusCode: Int,
        headers: [String: String] = [:]
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
    }

    private static func requestBodyString(from request: URLRequest) -> String? {
        guard let data = requestBodyData(from: request) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func requestBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let chunkSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: chunkSize)
            if read < 0 {
                break
            }
            if read == 0 {
                break
            }
            data.append(buffer, count: read)
        }

        if data.isEmpty {
            return nil
        }
        return data
    }

    private static func requestIncludesFileURI(_ request: URLRequest, expectedURI: String) -> Bool {
        guard let bodyData = requestBodyData(from: request) else {
            return false
        }
        guard let payload = try? JSONDecoder().decode(GenerateContentRequestProbe.self, from: bodyData) else {
            return false
        }
        return payload.contents
            .flatMap(\.parts)
            .compactMap { $0.fileData?.fileURI }
            .contains(expectedURI)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QueueURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private struct GenerateContentRequestProbe: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                struct FileData: Decodable {
                    let fileURI: String

                    enum CodingKeys: String, CodingKey {
                        case fileURI = "file_uri"
                    }
                }

                let fileData: FileData?

                enum CodingKeys: String, CodingKey {
                    case fileData = "file_data"
                }
            }

            let parts: [Part]
        }

        let contents: [Content]
    }
}
