import Foundation
import Testing
@testable import TaskAgentMacOSApp

private final class MockLLMClient: LLMClient {
    var output: String
    var lastPrompt: String?
    var lastModel: String?
    var shouldThrow = false

    init(output: String) {
        self.output = output
    }

    func analyzeVideo(at url: URL, prompt: String, model: String) async throws -> String {
        if shouldThrow {
            throw LLMClientError.notConfigured
        }
        lastPrompt = prompt
        lastModel = model
        return output
    }
}

struct TaskExtractionServiceTests {
    @Test
    func extractHeartbeatMarkdownReturnsValidatedOutput() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let promptDir = tempRoot.appendingPathComponent("task_extraction", isDirectory: true)
        try fm.createDirectory(at: promptDir, withIntermediateDirectories: true)
        try """
        version: v2
        llm: gemini-3-pro
        """.write(
            to: promptDir.appendingPathComponent("config.yaml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "Prompt body".write(
            to: promptDir.appendingPathComponent("prompt.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let recordingURL = tempRoot.appendingPathComponent("sample.mp4", isDirectory: false)
        try Data("fake-video".utf8).write(to: recordingURL)

        let llm = MockLLMClient(output: """
        # Task
        TaskDetected: true
        Status: TASK_FOUND
        NoTaskReason: NONE
        Title: Submit expense report
        Goal: Submit this month's expense report
        AppsObserved:
        - Browser
        
        ## Questions
        - None.
        """)
        let promptCatalog = PromptCatalogService(promptsRootURL: tempRoot, fileManager: fm)
        let service = TaskExtractionService(fileManager: fm, promptCatalog: promptCatalog, llmClient: llm)

        let result = try await service.extractHeartbeatMarkdown(from: recordingURL)

        #expect(result.taskDetected)
        #expect(result.promptVersion == "v2")
        #expect(result.llm == "gemini-3-pro")
        #expect(result.heartbeatMarkdown.contains("# Task"))
        #expect(result.heartbeatMarkdown.contains("## Questions"))
        #expect(!result.heartbeatMarkdown.contains("TaskDetected:"))
        #expect(!result.heartbeatMarkdown.contains("Status:"))
        #expect(!result.heartbeatMarkdown.contains("NoTaskReason:"))
        #expect(llm.lastPrompt == "Prompt body")
        #expect(llm.lastModel == "gemini-3-pro")
    }

    @Test
    func extractHeartbeatMarkdownFailsWhenModelOutputIsMalformed() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let promptDir = tempRoot.appendingPathComponent("task_extraction", isDirectory: true)
        try fm.createDirectory(at: promptDir, withIntermediateDirectories: true)
        try """
        version: v2
        llm: gemini-3-pro
        """.write(
            to: promptDir.appendingPathComponent("config.yaml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "Prompt body".write(
            to: promptDir.appendingPathComponent("prompt.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let recordingURL = tempRoot.appendingPathComponent("sample.mp4", isDirectory: false)
        try Data("fake-video".utf8).write(to: recordingURL)

        let llm = MockLLMClient(output: """
        # Task
        Status: TASK_FOUND
        NoTaskReason: NONE
        Title: Missing task-detected field

        ## Questions
        - None.
        """)
        let promptCatalog = PromptCatalogService(promptsRootURL: tempRoot, fileManager: fm)
        let service = TaskExtractionService(fileManager: fm, promptCatalog: promptCatalog, llmClient: llm)

        do {
            _ = try await service.extractHeartbeatMarkdown(from: recordingURL)
            #expect(Bool(false))
        } catch {
            guard case TaskExtractionServiceError.invalidModelOutput(let message) = error else {
                #expect(Bool(false))
                return
            }
            #expect(message.contains("TaskDetected"))
        }
    }

    @Test
    func extractHeartbeatMarkdownSupportsNoTaskWithoutPersistingControlFields() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let promptDir = tempRoot.appendingPathComponent("task_extraction", isDirectory: true)
        try fm.createDirectory(at: promptDir, withIntermediateDirectories: true)
        try """
        version: v2
        llm: gemini-3-pro
        """.write(
            to: promptDir.appendingPathComponent("config.yaml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "Prompt body".write(
            to: promptDir.appendingPathComponent("prompt.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let recordingURL = tempRoot.appendingPathComponent("sample.mp4", isDirectory: false)
        try Data("fake-video".utf8).write(to: recordingURL)

        let llm = MockLLMClient(output: """
        # Task
        TaskDetected: false
        Status: NO_TASK
        NoTaskReason: NON_TASK_CONTENT
        Title: N/A
        Goal: N/A
        AppsObserved:
        - N/A
        PreferredDemonstratedApproach:
        - N/A
        ExecutionPolicy: Use demonstrated flow when practical, but any valid method is acceptable if it reaches the same goal and respects constraints.
        HardConstraints:
        - N/A
        SuccessCriteria:
        - N/A
        SuggestedPlan:
        1. N/A
        AlternativeValidApproaches:
        - N/A
        Evidence:
        - [00:00-00:05] Non-task content.

        ## Questions
        - None.
        """)
        let promptCatalog = PromptCatalogService(promptsRootURL: tempRoot, fileManager: fm)
        let service = TaskExtractionService(fileManager: fm, promptCatalog: promptCatalog, llmClient: llm)

        let result = try await service.extractHeartbeatMarkdown(from: recordingURL)

        #expect(!result.taskDetected)
        #expect(!result.heartbeatMarkdown.contains("TaskDetected:"))
        #expect(!result.heartbeatMarkdown.contains("Status:"))
        #expect(!result.heartbeatMarkdown.contains("NoTaskReason:"))
        #expect(result.heartbeatMarkdown.contains("Title: N/A"))
    }
}
