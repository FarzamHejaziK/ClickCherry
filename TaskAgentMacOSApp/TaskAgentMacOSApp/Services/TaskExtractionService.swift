import Foundation

struct TaskExtractionResult: Equatable {
    let heartbeatMarkdown: String
    let promptVersion: String
    let llm: String
    let taskDetected: Bool
}

enum TaskExtractionServiceError: Error, Equatable {
    case recordingNotFound
    case invalidModelOutput(String)
}

struct TaskExtractionService {
    private let fileManager: FileManager
    private let promptCatalog: PromptCatalogService
    private let llmClient: any LLMClient

    init(
        fileManager: FileManager = .default,
        promptCatalog: PromptCatalogService = PromptCatalogService(),
        llmClient: any LLMClient = UnconfiguredLLMClient()
    ) {
        self.fileManager = fileManager
        self.promptCatalog = promptCatalog
        self.llmClient = llmClient
    }

    func extractHeartbeatMarkdown(
        from recordingURL: URL,
        promptName: String = "task_extraction"
    ) async throws -> TaskExtractionResult {
        guard fileManager.fileExists(atPath: recordingURL.path) else {
            throw TaskExtractionServiceError.recordingNotFound
        }

        let promptTemplate = try promptCatalog.loadPrompt(named: promptName)
        let rawOutput = try await llmClient.analyzeVideo(
            at: recordingURL,
            prompt: promptTemplate.prompt,
            model: promptTemplate.config.llm
        )
        let normalizedOutput = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)

        try validateOutput(normalizedOutput)
        let taskDetected = parseTaskDetected(normalizedOutput)
        let sanitizedHeartbeat = sanitizeHeartbeat(normalizedOutput)

        return TaskExtractionResult(
            heartbeatMarkdown: sanitizedHeartbeat,
            promptVersion: promptTemplate.config.version,
            llm: promptTemplate.config.llm,
            taskDetected: taskDetected
        )
    }

    private func validateOutput(_ output: String) throws {
        let lines = trimmedLines(from: output)

        guard lines.contains("# Task") else {
            throw TaskExtractionServiceError.invalidModelOutput("Missing '# Task' section.")
        }
        guard lines.contains("## Questions") else {
            throw TaskExtractionServiceError.invalidModelOutput("Missing '## Questions' section.")
        }
        guard fieldValue(named: "TaskDetected", in: lines) != nil else {
            throw TaskExtractionServiceError.invalidModelOutput("Missing required field 'TaskDetected'.")
        }
        guard fieldValue(named: "Status", in: lines) != nil else {
            throw TaskExtractionServiceError.invalidModelOutput("Missing required field 'Status'.")
        }
        guard fieldValue(named: "NoTaskReason", in: lines) != nil else {
            throw TaskExtractionServiceError.invalidModelOutput("Missing required field 'NoTaskReason'.")
        }

        let taskDetectedValue = fieldValue(named: "TaskDetected", in: lines)?
            .lowercased()

        guard taskDetectedValue == "true" || taskDetectedValue == "false" else {
            throw TaskExtractionServiceError.invalidModelOutput("TaskDetected must be 'true' or 'false'.")
        }
    }

    private func parseTaskDetected(_ output: String) -> Bool {
        let lines = trimmedLines(from: output)
        let value = fieldValue(named: "TaskDetected", in: lines)?
            .lowercased()

        return value == "true"
    }

    private func sanitizeHeartbeat(_ output: String) -> String {
        let filtered = output
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return !(trimmed.hasPrefix("taskdetected:")
                    || trimmed.hasPrefix("status:")
                    || trimmed.hasPrefix("notaskreason:"))
            }

        return filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func trimmedLines(from output: String) -> [String] {
        output.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func fieldValue(named field: String, in lines: [String]) -> String? {
        let normalizedField = field.lowercased()

        for line in lines {
            guard let separator = line.firstIndex(of: ":") else {
                continue
            }

            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard key == normalizedField else {
                continue
            }

            let valueStart = line.index(after: separator)
            let value = line[valueStart...].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        return nil
    }
}
