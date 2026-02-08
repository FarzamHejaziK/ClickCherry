import Foundation
import Testing
@testable import TaskAgentMacOSApp

struct PromptCatalogServiceTests {
    @Test
    func loadPromptReadsPromptMarkdownAndYamlConfig() throws {
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

        let service = PromptCatalogService(promptsRootURL: tempRoot, fileManager: fm)
        let loaded = try service.loadPrompt(named: "task_extraction")

        #expect(loaded.name == "task_extraction")
        #expect(loaded.prompt == "Prompt body")
        #expect(loaded.config.version == "v2")
        #expect(loaded.config.llm == "gemini-3-pro")
    }

    @Test
    func loadPromptFailsWhenRequiredConfigKeyMissing() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let promptDir = tempRoot.appendingPathComponent("task_extraction", isDirectory: true)
        try fm.createDirectory(at: promptDir, withIntermediateDirectories: true)
        try """
        version: v2
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

        let service = PromptCatalogService(promptsRootURL: tempRoot, fileManager: fm)

        do {
            _ = try service.loadPrompt(named: "task_extraction")
            #expect(Bool(false))
        } catch {
            guard case PromptCatalogError.invalidConfig(let message) = error else {
                #expect(Bool(false))
                return
            }
            #expect(message.contains("llm"))
        }
    }
}
