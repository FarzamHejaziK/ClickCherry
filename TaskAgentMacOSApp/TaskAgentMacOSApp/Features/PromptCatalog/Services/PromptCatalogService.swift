import Foundation

struct PromptTemplate: Equatable {
    let name: String
    let prompt: String
    let config: PromptConfig
    let sourceURL: URL?
}

struct PromptConfig: Equatable {
    let version: String
    let llm: String
    let reasoningEffort: String?
    let reasoningSummary: String?
}

enum PromptCatalogError: Error, Equatable {
    case promptsRootNotFound
    case promptNotFound(String)
    case configNotFound(String)
    case invalidConfig(String)
}

struct PromptCatalogService {
    private let fileManager: FileManager
    private let promptsRootURLs: [URL]

    init(promptsRootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let promptsRootURL {
            self.promptsRootURLs = [promptsRootURL]
        } else {
            self.promptsRootURLs = Self.resolveDefaultPromptsRoots(fileManager: fileManager)
        }
    }

    func loadPrompt(named promptName: String) throws -> PromptTemplate {
        guard !promptsRootURLs.isEmpty else {
            throw PromptCatalogError.promptsRootNotFound
        }

        var foundPromptDirectory = false
        var foundConfigFile = false
        var foundPromptFile = false
        var firstParseError: PromptCatalogError?

        for promptsRootURL in promptsRootURLs {
            let promptDirectory = promptsRootURL.appendingPathComponent(promptName, isDirectory: true)
            guard fileManager.fileExists(atPath: promptDirectory.path) else {
                continue
            }
            foundPromptDirectory = true

            let promptURL = promptDirectory.appendingPathComponent("prompt.md", isDirectory: false)
            let configURL = promptDirectory.appendingPathComponent("config.yaml", isDirectory: false)
            guard fileManager.fileExists(atPath: configURL.path) else {
                continue
            }
            foundConfigFile = true

            do {
                let configRaw = try String(contentsOf: configURL, encoding: .utf8)
                let topLevelConfig = try parseConfig(configRaw, promptName: promptName)

                let versionedDirectory = promptDirectory.appendingPathComponent(topLevelConfig.version, isDirectory: true)
                let versionedPromptURL = versionedDirectory.appendingPathComponent("prompt.md", isDirectory: false)
                let resolvedPromptURL: URL
                if fileManager.fileExists(atPath: versionedPromptURL.path) {
                    resolvedPromptURL = versionedPromptURL
                } else if fileManager.fileExists(atPath: promptURL.path) {
                    resolvedPromptURL = promptURL
                } else {
                    continue
                }
                foundPromptFile = true

                let prompt = try String(contentsOf: resolvedPromptURL, encoding: .utf8)
                return PromptTemplate(
                    name: promptName,
                    prompt: prompt,
                    config: topLevelConfig,
                    sourceURL: resolvedPromptURL
                )
            } catch let error as PromptCatalogError {
                if firstParseError == nil {
                    firstParseError = error
                }
            } catch {
                if firstParseError == nil {
                    firstParseError = .invalidConfig("Failed to load prompt '\(promptName)'")
                }
            }
        }

        if let firstParseError {
            throw firstParseError
        }
        if !foundPromptDirectory || !foundPromptFile {
            throw PromptCatalogError.promptNotFound(promptName)
        }
        if !foundConfigFile {
            throw PromptCatalogError.configNotFound(promptName)
        }
        throw PromptCatalogError.promptNotFound(promptName)
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

        return PromptConfig(
            version: version,
            llm: llm,
            reasoningEffort: values["reasoning_effort"],
            reasoningSummary: values["reasoning_summary"]
        )
    }

    private static func resolveDefaultPromptsRoots(fileManager: FileManager) -> [URL] {
        var candidates: [URL] = []

        #if DEBUG
        let sourceDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        if let sourcePrompts = findPromptsRoot(startingAt: sourceDirectory, fileManager: fileManager) {
            candidates.append(sourcePrompts)
        }
        #endif

        if let bundlePrompts = Bundle.main.resourceURL?.appendingPathComponent("Prompts", isDirectory: true) {
            candidates.append(bundlePrompts)
        }

        var seenPaths: Set<String> = []
        return candidates.filter { candidate in
            guard fileManager.fileExists(atPath: candidate.path) else {
                return false
            }
            return seenPaths.insert(candidate.path).inserted
        }
    }

    private static func findPromptsRoot(startingAt directory: URL, fileManager: FileManager) -> URL? {
        var currentDirectory = directory

        while true {
            let resourcesPrompts = currentDirectory
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("Prompts", isDirectory: true)
            if fileManager.fileExists(atPath: resourcesPrompts.path) {
                return resourcesPrompts
            }

            let legacyPrompts = currentDirectory.appendingPathComponent("Prompts", isDirectory: true)
            if fileManager.fileExists(atPath: legacyPrompts.path) {
                return legacyPrompts
            }

            let parentDirectory = currentDirectory.deletingLastPathComponent()
            if parentDirectory.path == currentDirectory.path {
                return nil
            }
            currentDirectory = parentDirectory
        }
    }
}
