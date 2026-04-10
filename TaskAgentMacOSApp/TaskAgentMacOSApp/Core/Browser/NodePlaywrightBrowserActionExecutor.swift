import Foundation

actor NodePlaywrightBrowserActionExecutor: BrowserActionExecutor {
    private struct ResolvedNodeExecutable: Sendable {
        var url: URL
        var searchedPaths: [String]
    }

    private struct SidecarState: Codable, Equatable, Sendable {
        var debuggingPort: Int?
        var selectedTargetID: String?
        var managedChromePID: Int32?
        var profileMode: String?
        var profileDirectory: String?
        var userDataDir: String?
        var profileDisplayName: String?

        enum CodingKeys: String, CodingKey {
            case debuggingPort = "debugging_port"
            case selectedTargetID = "selected_target_id"
            case managedChromePID = "managed_chrome_pid"
            case profileMode = "profile_mode"
            case profileDirectory = "profile_directory"
            case userDataDir = "user_data_dir"
            case profileDisplayName = "profile_display_name"
        }
    }

    private struct SidecarEnvelope<Payload: Encodable>: Encodable {
        var command: String
        var state: SidecarState
        var payload: Payload
    }

    private struct SidecarResponse<Payload: Decodable>: Decodable {
        var ok: Bool
        var message: String
        var state: SidecarState?
        var data: Payload?
        var error: String?
    }

    private struct EmptyPayload: Encodable {}

    private struct LaunchPayload: Encodable {
        var options: BrowserLaunchOptions?
    }

    private struct SelectionPayload: Encodable {
        var selection: BrowserTabSelection
    }

    private struct GotoPayload: Encodable {
        var url: String
    }

    private struct QueryPayload: Encodable {
        var query: BrowserElementQuery
    }

    private struct TypePayload: Encodable {
        var query: BrowserElementQuery
        var text: String
        var pressEnter: Bool

        enum CodingKeys: String, CodingKey {
            case query
            case text
            case pressEnter = "press_enter"
        }
    }

    private struct PressPayload: Encodable {
        var key: String
    }

    private struct WaitPayload: Encodable {
        var condition: BrowserWaitCondition
    }

    nonisolated private let nodeExecutableName: String
    nonisolated private let sidecarDirectoryURL: URL?
    nonisolated private let environment: [String: String]
    nonisolated private let additionalNodeSearchPaths: [String]
    nonisolated private let commonNodeSearchPaths: [String]
    private var state = SidecarState()

    init(
        sidecarDirectoryURL: URL? = nil,
        nodeExecutableName: String = "node",
        nodeSearchPaths: [String] = [],
        commonNodeSearchPaths: [String]? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.nodeExecutableName = nodeExecutableName
        self.additionalNodeSearchPaths = nodeSearchPaths
        self.commonNodeSearchPaths = commonNodeSearchPaths ?? Self.defaultCommonNodeSearchPaths(for: nodeExecutableName)
        self.environment = environment
        self.sidecarDirectoryURL = sidecarDirectoryURL ?? Self.resolveDefaultSidecarDirectory()
    }

    func attachOrLaunchChrome(options: BrowserLaunchOptions?) async throws -> BrowserSessionInfo {
        try await perform(
            command: "attach_or_launch_chrome",
            payload: LaunchPayload(options: options),
            expecting: BrowserSessionInfo.self
        )
    }

    func listTabs() async throws -> [BrowserTabInfo] {
        try await perform(command: "list_tabs", payload: EmptyPayload(), expecting: [BrowserTabInfo].self)
    }

    func selectTab(using selection: BrowserTabSelection) async throws -> BrowserTabInfo {
        try await perform(command: "select_tab", payload: SelectionPayload(selection: selection), expecting: BrowserTabInfo.self)
    }

    func goto(url: URL) async throws -> BrowserPageState {
        try await perform(command: "goto", payload: GotoPayload(url: url.absoluteString), expecting: BrowserPageState.self)
    }

    func click(query: BrowserElementQuery) async throws -> BrowserPageState {
        try await perform(command: "click", payload: QueryPayload(query: query), expecting: BrowserPageState.self)
    }

    func type(text: String, query: BrowserElementQuery, pressEnter: Bool) async throws -> BrowserPageState {
        try await perform(
            command: "type",
            payload: TypePayload(query: query, text: text, pressEnter: pressEnter),
            expecting: BrowserPageState.self
        )
    }

    func press(key: String) async throws -> BrowserPageState {
        try await perform(command: "press", payload: PressPayload(key: key), expecting: BrowserPageState.self)
    }

    func waitFor(_ condition: BrowserWaitCondition) async throws -> BrowserWaitResult {
        try await perform(command: "wait_for", payload: WaitPayload(condition: condition), expecting: BrowserWaitResult.self)
    }

    func snapshot() async throws -> BrowserSnapshot {
        try await perform(command: "snapshot", payload: EmptyPayload(), expecting: BrowserSnapshot.self)
    }

    func getURL() async throws -> String {
        try await perform(command: "get_url", payload: EmptyPayload(), expecting: String.self)
    }

    func getTitle() async throws -> String {
        try await perform(command: "get_title", payload: EmptyPayload(), expecting: String.self)
    }

    private func perform<Payload: Encodable, Response: Decodable>(
        command: String,
        payload: Payload,
        expecting responseType: Response.Type
    ) async throws -> Response {
        let scriptURL = try ensureSidecarIsAvailable()
        let resolvedNodeExecutable = try resolveNodeExecutable()
        let envelope = SidecarEnvelope(command: command, state: state, payload: payload)
        let requestData = try JSONEncoder().encode(envelope)

        let response: SidecarResponse<Response> = try await Task.detached(priority: .userInitiated) {
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let stdinPipe = Pipe()

            let process = Process()
            process.executableURL = resolvedNodeExecutable.url
            process.arguments = [scriptURL.path]
            process.currentDirectoryURL = scriptURL.deletingLastPathComponent()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = stdinPipe

            do {
                try process.run()
            } catch {
                throw BrowserActionExecutorError.nodeUnavailable(
                    Self.nodeUnavailableMessage(
                        searchedPaths: resolvedNodeExecutable.searchedPaths,
                        launchFailure: error.localizedDescription
                    )
                )
            }

            stdinPipe.fileHandleForWriting.write(requestData)
            try? stdinPipe.fileHandleForWriting.close()

            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard process.terminationStatus == 0 else {
                if process.terminationStatus == 127 || stderr.lowercased().contains("node") && stderr.lowercased().contains("not found") {
                    throw BrowserActionExecutorError.nodeUnavailable(
                        Self.nodeUnavailableMessage(
                            searchedPaths: resolvedNodeExecutable.searchedPaths,
                            launchFailure: stderr.isEmpty ? "Sidecar exited with status \(process.terminationStatus)." : stderr
                        )
                    )
                }
                throw BrowserActionExecutorError.executionFailed(stderr.isEmpty ? "Sidecar exited with status \(process.terminationStatus)." : stderr)
            }

            guard !stdout.isEmpty, let stdoutData = stdout.data(using: .utf8) else {
                throw BrowserActionExecutorError.invalidResponse
            }

            do {
                return try JSONDecoder().decode(SidecarResponse<Response>.self, from: stdoutData)
            } catch {
                if !stderr.isEmpty {
                    throw BrowserActionExecutorError.executionFailed(stderr)
                }
                throw BrowserActionExecutorError.invalidResponse
            }
        }.value

        if let updatedState = response.state {
            state = updatedState
        }

        guard response.ok else {
            throw mapSidecarError(code: response.error, message: response.message)
        }

        guard let data = response.data else {
            throw BrowserActionExecutorError.invalidResponse
        }
        return data
    }

    private func ensureSidecarIsAvailable() throws -> URL {
        let fileManager = FileManager.default
        guard let sidecarDirectoryURL else {
            throw BrowserActionExecutorError.sidecarNotFound("browser_sidecar")
        }

        let scriptURL = sidecarDirectoryURL.appendingPathComponent("browser_action.mjs", isDirectory: false)
        guard fileManager.fileExists(atPath: scriptURL.path) else {
            throw BrowserActionExecutorError.sidecarNotFound(scriptURL.path)
        }

        let playwrightPackageURL = sidecarDirectoryURL
            .appendingPathComponent("node_modules", isDirectory: true)
            .appendingPathComponent("playwright", isDirectory: true)
            .appendingPathComponent("package.json", isDirectory: false)

        guard fileManager.fileExists(atPath: playwrightPackageURL.path) else {
            throw BrowserActionExecutorError.sidecarDependenciesMissing(sidecarDirectoryURL.path)
        }

        return scriptURL
    }

    private func resolveNodeExecutable() throws -> ResolvedNodeExecutable {
        let fileManager = FileManager.default
        let searchedPaths = Self.nodeExecutableSearchPaths(
            nodeExecutableName: nodeExecutableName,
            environment: environment,
            additionalSearchPaths: additionalNodeSearchPaths,
            commonSearchPaths: commonNodeSearchPaths
        )

        for candidate in searchedPaths where fileManager.isExecutableFile(atPath: candidate) {
            return ResolvedNodeExecutable(url: URL(fileURLWithPath: candidate), searchedPaths: searchedPaths)
        }

        throw BrowserActionExecutorError.nodeUnavailable(Self.nodeUnavailableMessage(searchedPaths: searchedPaths))
    }

    private func mapSidecarError(code: String?, message: String) -> BrowserActionExecutorError {
        switch code {
        case "chrome_not_found":
            return .chromeNotFound
        case "invalid_url":
            return .invalidURL(message)
        case "missing_selector":
            return .missingSelector
        case "missing_value":
            return .missingValue
        case "node_unavailable":
            return .nodeUnavailable(message)
        default:
            return .executionFailed(message)
        }
    }

    nonisolated static func nodeExecutableSearchPaths(
        nodeExecutableName: String,
        environment: [String: String],
        additionalSearchPaths: [String],
        commonSearchPaths: [String]? = nil
    ) -> [String] {
        var candidates: [String] = []

        func append(_ path: String?) {
            guard let path else { return }
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !candidates.contains(trimmed) else { return }
            candidates.append(trimmed)
        }

        if nodeExecutableName.contains("/") {
            append(nodeExecutableName)
            return candidates
        }

        let pathDirectories = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        for directory in pathDirectories {
            append(URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(nodeExecutableName).path)
        }

        for searchPath in additionalSearchPaths {
            if searchPath.contains("/") {
                append(searchPath)
            }
        }

        for location in commonSearchPaths ?? defaultCommonNodeSearchPaths(for: nodeExecutableName) {
            append(location)
        }

        return candidates
    }

    nonisolated static func nodeUnavailableMessage(
        searchedPaths: [String],
        launchFailure: String? = nil
    ) -> String {
        let searchedSummary = searchedPaths.isEmpty
            ? "No node executable locations were available to search."
            : "Searched: \(searchedPaths.joined(separator: ", "))"
        if let launchFailure, !launchFailure.isEmpty {
            return "Node.js is required for browser automation but could not be launched. \(searchedSummary) Launch error: \(launchFailure)"
        }
        return "Node.js is required for browser automation but was not found. \(searchedSummary)"
    }

    nonisolated static func defaultCommonNodeSearchPaths(for nodeExecutableName: String) -> [String] {
        [
            "/opt/homebrew/bin/\(nodeExecutableName)",
            "/usr/local/bin/\(nodeExecutableName)",
            "/opt/local/bin/\(nodeExecutableName)",
            "/usr/bin/\(nodeExecutableName)"
        ]
    }

    nonisolated private static func resolveDefaultSidecarDirectory() -> URL? {
        let fileManager = FileManager.default
        var current = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

        while true {
            let candidate = current.appendingPathComponent("browser_sidecar", isDirectory: true)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }

            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
    }
}
