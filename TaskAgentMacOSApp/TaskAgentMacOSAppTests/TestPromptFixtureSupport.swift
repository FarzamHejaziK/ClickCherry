import Foundation
@testable import TaskAgentMacOSApp

enum TestPromptFixtureSupport {
    static func sourcePromptConfig(named promptName: String) throws -> PromptConfig {
        try PromptCatalogService().loadPrompt(named: promptName).config
    }

    @discardableResult
    static func writePromptFixture(
        named promptName: String,
        into promptsRoot: URL,
        promptBody: String,
        fileManager: FileManager = .default,
        version: String? = nil,
        llm: String? = nil,
        reasoningEffort: String? = nil,
        reasoningSummary: String? = nil
    ) throws -> PromptConfig {
        let sourceConfig = try sourcePromptConfig(named: promptName)
        let resolvedVersion = version ?? sourceConfig.version
        let resolvedLLM = llm ?? sourceConfig.llm
        let resolvedReasoningEffort = reasoningEffort ?? sourceConfig.reasoningEffort
        let resolvedReasoningSummary = reasoningSummary ?? sourceConfig.reasoningSummary

        let promptDir = promptsRoot.appendingPathComponent(promptName, isDirectory: true)
        try fileManager.createDirectory(at: promptDir, withIntermediateDirectories: true)
        var configLines = [
            "version: \(resolvedVersion)",
            "llm: \(resolvedLLM)"
        ]
        if let resolvedReasoningEffort {
            configLines.append("reasoning_effort: \(resolvedReasoningEffort)")
        }
        if let resolvedReasoningSummary {
            configLines.append("reasoning_summary: \(resolvedReasoningSummary)")
        }
        try configLines.joined(separator: "\n").appending("\n").write(
            to: promptDir.appendingPathComponent("config.yaml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try promptBody.write(
            to: promptDir.appendingPathComponent("prompt.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        return PromptConfig(
            version: resolvedVersion,
            llm: resolvedLLM,
            reasoningEffort: resolvedReasoningEffort,
            reasoningSummary: resolvedReasoningSummary
        )
    }
}
