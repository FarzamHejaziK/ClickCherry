import Foundation
import UniformTypeIdentifiers

enum GeminiLLMClientError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case failedToReadAPIKey
    case invalidRecording(String)
    case uploadInitializationFailed(String)
    case uploadFailed(String)
    case invalidUploadResponse
    case fileProcessingFailed(String)
    case fileProcessingTimedOut
    case generateFailed(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Gemini API key is not configured. Save one in Provider API Keys."
        case .failedToReadAPIKey:
            return "Failed to read Gemini API key from secure storage."
        case .invalidRecording(let reason):
            return "Recording is invalid for extraction: \(reason)"
        case .uploadInitializationFailed(let reason):
            return "Gemini upload initialization failed: \(reason)"
        case .uploadFailed(let reason):
            return "Gemini video upload failed: \(reason)"
        case .invalidUploadResponse:
            return "Gemini upload response was invalid."
        case .fileProcessingFailed(let reason):
            return "Gemini could not process the uploaded video: \(reason)"
        case .fileProcessingTimedOut:
            return "Gemini video processing timed out."
        case .generateFailed(let reason):
            return "Gemini task extraction request failed: \(reason)"
        case .emptyResponse:
            return "Gemini returned an empty extraction response."
        }
    }
}

final class GeminiVideoLLMClient: LLMClient {
    private let apiKeyStore: any APIKeyStore
    private let session: URLSession
    private let pollIntervalNanoseconds: UInt64
    private let maxPollAttempts: Int
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    init(
        apiKeyStore: any APIKeyStore,
        session: URLSession = .shared,
        pollIntervalNanoseconds: UInt64 = 2_000_000_000,
        maxPollAttempts: Int = 45
    ) {
        self.apiKeyStore = apiKeyStore
        self.session = session
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.maxPollAttempts = maxPollAttempts
        self.jsonEncoder = JSONEncoder()
        self.jsonDecoder = JSONDecoder()
        self.jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func analyzeVideo(at url: URL, prompt: String, model: String) async throws -> String {
        let apiKey = try resolveAPIKey()
        let recordingInfo = try resolveRecordingInfo(at: url)
        let uploadURL = try await startUpload(
            fileName: recordingInfo.fileName,
            mimeType: recordingInfo.mimeType,
            fileSize: recordingInfo.fileSize,
            apiKey: apiKey
        )
        let uploadedFile = try await uploadFile(
            to: uploadURL,
            recordingURL: url,
            mimeType: recordingInfo.mimeType,
            fileSize: recordingInfo.fileSize
        )
        let activeFile = try await waitForFileToBecomeActive(initialFile: uploadedFile, apiKey: apiKey)
        guard let fileURI = activeFile.uri, !fileURI.isEmpty else {
            throw GeminiLLMClientError.invalidUploadResponse
        }

        let output = try await generateContent(
            prompt: prompt,
            fileURI: fileURI,
            mimeType: recordingInfo.mimeType,
            model: resolveModelName(model),
            apiKey: apiKey
        )
        let normalized = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw GeminiLLMClientError.emptyResponse
        }
        return normalized
    }

    private func resolveAPIKey() throws -> String {
        do {
            guard let raw = try apiKeyStore.readKey(for: .gemini) else {
                throw GeminiLLMClientError.missingAPIKey
            }
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                throw GeminiLLMClientError.missingAPIKey
            }
            return key
        } catch let error as GeminiLLMClientError {
            throw error
        } catch {
            throw GeminiLLMClientError.failedToReadAPIKey
        }
    }

    private func resolveRecordingInfo(at url: URL) throws -> RecordingInfo {
        guard url.isFileURL else {
            throw GeminiLLMClientError.invalidRecording("Path is not a local file URL.")
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw GeminiLLMClientError.invalidRecording("File not found.")
        }

        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else {
                throw GeminiLLMClientError.invalidRecording("Path is not a regular file.")
            }
            guard let fileSize = values.fileSize, fileSize > 0 else {
                throw GeminiLLMClientError.invalidRecording("File is empty.")
            }

            let mimeType = if
                let type = UTType(filenameExtension: url.pathExtension),
                let preferredMIMEType = type.preferredMIMEType {
                preferredMIMEType
            } else {
                "application/octet-stream"
            }

            return RecordingInfo(
                fileName: url.lastPathComponent.isEmpty ? "recording.mp4" : url.lastPathComponent,
                fileSize: fileSize,
                mimeType: mimeType
            )
        } catch let error as GeminiLLMClientError {
            throw error
        } catch {
            throw GeminiLLMClientError.invalidRecording("File metadata could not be read.")
        }
    }

    private func startUpload(
        fileName: String,
        mimeType: String,
        fileSize: Int,
        apiKey: String
    ) async throws -> URL {
        var request = URLRequest(url: try makeURL(path: "/upload/v1beta/files", apiKey: apiKey))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        request.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        request.setValue(String(fileSize), forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        request.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        request.httpBody = try jsonEncoder.encode(UploadStartRequest(file: .init(displayName: fileName)))

        let (data, response) = try await data(for: request, stage: .uploadInit)
        guard (200..<300).contains(response.statusCode) else {
            throw GeminiLLMClientError.uploadInitializationFailed(serverMessage(from: data, statusCode: response.statusCode))
        }
        guard let uploadURLString = response.value(forHTTPHeaderField: "X-Goog-Upload-URL"),
              let uploadURL = URL(string: uploadURLString) else {
            throw GeminiLLMClientError.invalidUploadResponse
        }

        return uploadURL
    }

    private func uploadFile(
        to uploadURL: URL,
        recordingURL: URL,
        mimeType: String,
        fileSize: Int
    ) async throws -> GeminiFile {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        request.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        request.setValue(String(fileSize), forHTTPHeaderField: "Content-Length")
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")

        let (data, response) = try await upload(for: request, fromFile: recordingURL, stage: .upload)
        guard (200..<300).contains(response.statusCode) else {
            throw GeminiLLMClientError.uploadFailed(serverMessage(from: data, statusCode: response.statusCode))
        }

        guard let uploadedFile = try decodeGeminiFile(from: data, stage: .upload) else {
            throw GeminiLLMClientError.invalidUploadResponse
        }
        return uploadedFile
    }

    private func waitForFileToBecomeActive(initialFile: GeminiFile, apiKey: String) async throws -> GeminiFile {
        var current = initialFile
        for attempt in 0..<maxPollAttempts {
            let state = (current.state ?? "").uppercased()
            if state == "ACTIVE" {
                return current
            }
            if state == "FAILED" {
                let reason = current.error?.message ?? "Gemini marked file as FAILED."
                throw GeminiLLMClientError.fileProcessingFailed(reason)
            }

            if attempt == maxPollAttempts - 1 {
                break
            }

            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            current = try await fetchFile(named: current.name, apiKey: apiKey)
        }
        throw GeminiLLMClientError.fileProcessingTimedOut
    }

    private func fetchFile(named fileName: String, apiKey: String) async throws -> GeminiFile {
        let normalized = fileName.hasPrefix("/") ? String(fileName.dropFirst()) : fileName
        var request = URLRequest(url: try makeURL(path: "/v1beta/\(normalized)", apiKey: apiKey))
        request.httpMethod = "GET"

        let (data, response) = try await data(for: request, stage: .poll)
        guard (200..<300).contains(response.statusCode) else {
            throw GeminiLLMClientError.fileProcessingFailed(serverMessage(from: data, statusCode: response.statusCode))
        }
        guard let polledFile = try decodeGeminiFile(from: data, stage: .poll) else {
            throw GeminiLLMClientError.fileProcessingFailed("Gemini file poll response was invalid.")
        }
        return polledFile
    }

    private func generateContent(
        prompt: String,
        fileURI: String,
        mimeType: String,
        model: String,
        apiKey: String
    ) async throws -> String {
        var request = URLRequest(
            url: try makeURL(path: "/v1beta/models/\(model):generateContent", apiKey: apiKey)
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try jsonEncoder.encode(
            GenerateContentRequest(contents: [
                .init(parts: [
                    .init(text: prompt, fileData: nil),
                    .init(text: nil, fileData: .init(mimeType: mimeType, fileURI: fileURI))
                ])
            ])
        )

        let (data, response) = try await data(for: request, stage: .generate)
        guard (200..<300).contains(response.statusCode) else {
            throw GeminiLLMClientError.generateFailed(serverMessage(from: data, statusCode: response.statusCode))
        }
        guard let payload = try decode(GenerateContentResponse.self, from: data, stage: .generate) else {
            throw GeminiLLMClientError.generateFailed("Gemini response format was invalid.")
        }

        let text = payload.candidates?
            .compactMap { $0.content?.parts }
            .flatMap { $0 }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let text, !text.isEmpty else {
            throw GeminiLLMClientError.emptyResponse
        }
        return text
    }

    private func makeURL(path: String, apiKey: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "generativelanguage.googleapis.com"
        components.path = path
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            throw GeminiLLMClientError.generateFailed("Failed to build Gemini request URL.")
        }
        return url
    }

    private func resolveModelName(_ configuredModel: String) -> String {
        var normalized = configuredModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("models/") {
            normalized = String(normalized.dropFirst("models/".count))
        }
        if normalized.lowercased() == "gemini-3-pro" {
            return "gemini-3-pro-preview"
        }
        if normalized.lowercased() == "gemini-3-flash" {
            return "gemini-3-flash-preview"
        }
        return normalized
    }

    private func data(
        for request: URLRequest,
        stage: RequestStage
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiLLMClientError.generateFailed("Unexpected non-HTTP response.")
            }
            return (data, httpResponse)
        } catch let error as GeminiLLMClientError {
            throw error
        } catch {
            throw mappedTransportError(for: stage, underlyingError: error)
        }
    }

    private func upload(
        for request: URLRequest,
        fromFile fileURL: URL,
        stage: RequestStage
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.upload(for: request, fromFile: fileURL)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiLLMClientError.uploadFailed("Unexpected non-HTTP upload response.")
            }
            return (data, httpResponse)
        } catch let error as GeminiLLMClientError {
            throw error
        } catch {
            throw mappedTransportError(for: stage, underlyingError: error)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, stage: RequestStage) throws -> T? {
        guard !data.isEmpty else {
            return nil
        }
        do {
            return try jsonDecoder.decode(type, from: data)
        } catch {
            throw mappedDecodeError(for: stage)
        }
    }

    private func decodeGeminiFile(from data: Data, stage: RequestStage) throws -> GeminiFile? {
        guard !data.isEmpty else {
            return nil
        }

        if let envelope = try? jsonDecoder.decode(GeminiFileEnvelope.self, from: data) {
            return envelope.file
        }
        if let file = try? jsonDecoder.decode(GeminiFile.self, from: data) {
            return file
        }
        throw mappedDecodeError(for: stage)
    }

    private func serverMessage(from data: Data, statusCode: Int) -> String {
        if let parsed = try? jsonDecoder.decode(GeminiErrorEnvelope.self, from: data),
           let message = parsed.error.message,
           !message.isEmpty {
            return message
        }
        return "HTTP \(statusCode)"
    }

    private func mappedTransportError(for stage: RequestStage, underlyingError: Error) -> GeminiLLMClientError {
        let message = (underlyingError as NSError).localizedDescription
        switch stage {
        case .uploadInit:
            return .uploadInitializationFailed(message)
        case .upload:
            return .uploadFailed(message)
        case .poll:
            return .fileProcessingFailed(message)
        case .generate:
            return .generateFailed(message)
        }
    }

    private func mappedDecodeError(for stage: RequestStage) -> GeminiLLMClientError {
        switch stage {
        case .uploadInit:
            return .uploadInitializationFailed("Gemini upload start response was invalid.")
        case .upload:
            return .uploadFailed("Gemini upload response was invalid.")
        case .poll:
            return .fileProcessingFailed("Gemini file poll response was invalid.")
        case .generate:
            return .generateFailed("Gemini generation response was invalid.")
        }
    }
}

private extension GeminiVideoLLMClient {
    enum RequestStage {
        case uploadInit
        case upload
        case poll
        case generate
    }

    struct RecordingInfo {
        let fileName: String
        let fileSize: Int
        let mimeType: String
    }

    struct UploadStartRequest: Encodable {
        struct FileMetadata: Encodable {
            let displayName: String

            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
            }
        }

        let file: FileMetadata
    }

    struct GeminiFileEnvelope: Decodable {
        let file: GeminiFile
    }

    struct GeminiFile: Decodable {
        let name: String
        let uri: String?
        let state: String?
        let error: GeminiErrorMessage?
    }

    struct GeminiErrorMessage: Decodable {
        let message: String?
    }

    struct GenerateContentRequest: Encodable {
        struct Content: Encodable {
            let parts: [Part]
        }

        struct Part: Encodable {
            let text: String?
            let fileData: FileData?

            enum CodingKeys: String, CodingKey {
                case text
                case fileData = "file_data"
            }
        }

        struct FileData: Encodable {
            let mimeType: String
            let fileURI: String

            enum CodingKeys: String, CodingKey {
                case mimeType = "mime_type"
                case fileURI = "file_uri"
            }
        }

        let contents: [Content]
    }

    struct GenerateContentResponse: Decodable {
        struct Candidate: Decodable {
            let content: CandidateContent?
        }

        struct CandidateContent: Decodable {
            let parts: [CandidatePart]?
        }

        struct CandidatePart: Decodable {
            let text: String?
        }

        let candidates: [Candidate]?
    }

    struct GeminiErrorEnvelope: Decodable {
        struct GeminiErrorBody: Decodable {
            let message: String?
        }

        let error: GeminiErrorBody
    }
}
