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

        let sourceConfig = try TestPromptFixtureSupport.sourcePromptConfig(named: "task_extraction")
        try TestPromptFixtureSupport.writePromptFixture(
            named: "task_extraction",
            into: tempRoot,
            promptBody: "Prompt body",
            fileManager: fm
        )

        let service = PromptCatalogService(promptsRootURL: tempRoot, fileManager: fm)
        let loaded = try service.loadPrompt(named: "task_extraction")

        #expect(loaded.name == "task_extraction")
        #expect(loaded.prompt == "Prompt body")
        #expect(loaded.config.version == sourceConfig.version)
        #expect(loaded.config.llm == sourceConfig.llm)
        #expect(loaded.config.reasoningEffort == sourceConfig.reasoningEffort)
        #expect(loaded.config.reasoningSummary == sourceConfig.reasoningSummary)
        #expect(loaded.sourceURL?.lastPathComponent == "prompt.md")
    }

    @Test
    func defaultCatalogFindsReorganizedSourcePrompts() throws {
        let loaded = try PromptCatalogService().loadPrompt(named: "execution_agent_openai")

        #expect(loaded.config.version == "v4")
        #expect(loaded.sourceURL?.path.contains("/Resources/Prompts/execution_agent_openai/") == true)
    }

    @Test
    func executionAgentPromptRequiresVerificationAfterVisualClicks() throws {
        let loaded = try PromptCatalogService().loadPrompt(named: "execution_agent_openai")

        #expect(loaded.prompt.contains("If webpage content can be targeted through browser MCP tools, use those tools first"))
        #expect(loaded.prompt.contains("Only call MCP browser tools that are actually present in `AVAILABLE_MCP_TOOLS`"))
        #expect(loaded.prompt.contains("Do not use browser MCP tools for browser chrome, OS-level prompts, file pickers, or non-DOM surfaces"))
        #expect(loaded.prompt.contains("use `open_app` to open or focus an app instead of clicking Dock or app icons"))
        #expect(loaded.prompt.contains("do not return `SUCCESS` unless the latest screenshot verifies the intended outcome"))
        #expect(loaded.prompt.contains("\"verification_status\":\"verified|not_needed|unclear\""))
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

    @Test
    func loadPromptUsesVersionedPromptSelectedByTopLevelConfig() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let promptDir = tempRoot.appendingPathComponent("execution_agent_openai", isDirectory: true)
        let versionDir = promptDir.appendingPathComponent("v3", isDirectory: true)
        try fm.createDirectory(at: versionDir, withIntermediateDirectories: true)

        try """
        version: v3
        llm: gpt-5.3-codex
        """.write(
            to: promptDir.appendingPathComponent("config.yaml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "Flat prompt".write(
            to: promptDir.appendingPathComponent("prompt.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try """
        version: ignored
        llm: ignored-model
        """.write(
            to: versionDir.appendingPathComponent("config.yaml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "Versioned prompt".write(
            to: versionDir.appendingPathComponent("prompt.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let service = PromptCatalogService(promptsRootURL: tempRoot, fileManager: fm)
        let loaded = try service.loadPrompt(named: "execution_agent_openai")

        #expect(loaded.prompt == "Versioned prompt")
        #expect(loaded.config.version == "v3")
        #expect(loaded.config.llm == "gpt-5.3-codex")
        #expect(loaded.sourceURL?.path.hasSuffix("/execution_agent_openai/v3/prompt.md") == true)
    }

    @Test
    func loadPromptUsesVersionedPromptWithoutRequiringFlatPromptFile() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let promptDir = tempRoot.appendingPathComponent("execution_agent_openai", isDirectory: true)
        let versionDir = promptDir.appendingPathComponent("v2", isDirectory: true)
        try fm.createDirectory(at: versionDir, withIntermediateDirectories: true)

        try """
        version: v2
        llm: gpt-5.3-codex
        """.write(
            to: promptDir.appendingPathComponent("config.yaml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "Versioned only prompt".write(
            to: versionDir.appendingPathComponent("prompt.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let service = PromptCatalogService(promptsRootURL: tempRoot, fileManager: fm)
        let loaded = try service.loadPrompt(named: "execution_agent_openai")

        #expect(loaded.prompt == "Versioned only prompt")
        #expect(loaded.config.version == "v2")
        #expect(loaded.config.llm == "gpt-5.3-codex")
        #expect(loaded.sourceURL?.path.hasSuffix("/execution_agent_openai/v2/prompt.md") == true)
    }

    @Test
    func loadPromptFallsBackToFlatPromptWhenSelectedVersionFolderIsMissing() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let promptDir = tempRoot.appendingPathComponent("execution_agent_openai", isDirectory: true)
        try fm.createDirectory(at: promptDir, withIntermediateDirectories: true)

        try """
        version: v9
        llm: gpt-5.3-codex
        """.write(
            to: promptDir.appendingPathComponent("config.yaml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "Flat prompt".write(
            to: promptDir.appendingPathComponent("prompt.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let service = PromptCatalogService(promptsRootURL: tempRoot, fileManager: fm)
        let loaded = try service.loadPrompt(named: "execution_agent_openai")

        #expect(loaded.prompt == "Flat prompt")
        #expect(loaded.config.version == "v9")
        #expect(loaded.config.llm == "gpt-5.3-codex")
        #expect(loaded.sourceURL?.path.hasSuffix("/execution_agent_openai/prompt.md") == true)
    }

    @Test
    func loadPromptParsesOptionalReasoningSettingsFromTopLevelConfig() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let promptDir = tempRoot.appendingPathComponent("execution_agent_openai", isDirectory: true)
        let versionDir = promptDir.appendingPathComponent("v2", isDirectory: true)
        try fm.createDirectory(at: versionDir, withIntermediateDirectories: true)

        try """
        version: v2
        llm: gpt-5.3-codex
        reasoning_effort: medium
        reasoning_summary: auto
        """.write(
            to: promptDir.appendingPathComponent("config.yaml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "Versioned prompt".write(
            to: versionDir.appendingPathComponent("prompt.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let service = PromptCatalogService(promptsRootURL: tempRoot, fileManager: fm)
        let loaded = try service.loadPrompt(named: "execution_agent_openai")

        #expect(loaded.config.reasoningEffort == "medium")
        #expect(loaded.config.reasoningSummary == "auto")
    }
}
