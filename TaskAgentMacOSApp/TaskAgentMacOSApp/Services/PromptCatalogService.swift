import Foundation

struct PromptTemplate: Equatable {
    let name: String
    let prompt: String
    let config: PromptConfig
}

struct PromptConfig: Equatable {
    let version: String
    let llm: String
}

enum PromptCatalogError: Error, Equatable {
    case promptsRootNotFound
    case promptNotFound(String)
    case configNotFound(String)
    case invalidConfig(String)
}

struct PromptCatalogService {
    private let fileManager: FileManager
    private let promptsRootURL: URL?

    init(promptsRootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.promptsRootURL = promptsRootURL ?? Self.resolveDefaultPromptsRoot(fileManager: fileManager)
    }

    func loadPrompt(named promptName: String) throws -> PromptTemplate {
        guard let promptsRootURL else {
            throw PromptCatalogError.promptsRootNotFound
        }

        let promptDirectory = promptsRootURL.appendingPathComponent(promptName, isDirectory: true)
        guard fileManager.fileExists(atPath: promptDirectory.path) else {
            throw PromptCatalogError.promptNotFound(promptName)
        }

        let promptURL = promptDirectory.appendingPathComponent("prompt.md", isDirectory: false)
        guard fileManager.fileExists(atPath: promptURL.path) else {
            throw PromptCatalogError.promptNotFound(promptName)
        }

        let configURL = promptDirectory.appendingPathComponent("config.yaml", isDirectory: false)
        guard fileManager.fileExists(atPath: configURL.path) else {
            throw PromptCatalogError.configNotFound(promptName)
        }

        let prompt = try String(contentsOf: promptURL, encoding: .utf8)
        let configRaw = try String(contentsOf: configURL, encoding: .utf8)
        let config = try parseConfig(configRaw, promptName: promptName)

        return PromptTemplate(name: promptName, prompt: prompt, config: config)
    }

    private func parseConfig(_ raw: String, promptName: String) throws -> PromptConfig {
        var values: [String: String] = [:]

        let lines = raw.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            guard let separator = trimmed.firstIndex(of: ":") else {
                throw PromptCatalogError.invalidConfig("Invalid config line for prompt '\(promptName)': \(line)")
            }

            let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = trimmed.index(after: separator)
            var value = String(trimmed[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            values[key] = value
        }

        guard let version = values["version"], !version.isEmpty else {
            throw PromptCatalogError.invalidConfig("Missing required key 'version' for prompt '\(promptName)'")
        }
        guard let llm = values["llm"], !llm.isEmpty else {
            throw PromptCatalogError.invalidConfig("Missing required key 'llm' for prompt '\(promptName)'")
        }

        return PromptConfig(version: version, llm: llm)
    }

    private static func resolveDefaultPromptsRoot(fileManager: FileManager) -> URL? {
        var candidates: [URL] = []

        if let bundlePrompts = Bundle.main.resourceURL?.appendingPathComponent("Prompts", isDirectory: true) {
            candidates.append(bundlePrompts)
        }

        #if DEBUG
        let sourcePrompts = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Prompts", isDirectory: true)
        candidates.append(sourcePrompts)
        #endif

        return candidates.first(where: { fileManager.fileExists(atPath: $0.path) })
    }
}
