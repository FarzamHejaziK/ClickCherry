import Foundation

nonisolated final class MCPStdioTransport: @unchecked Sendable {
    typealias MessageHandler = @Sendable (Data) -> Void
    typealias DisconnectHandler = @Sendable (String) -> Void
    typealias TextHandler = @Sendable (String) -> Void

    private let fileManager: FileManager
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let parseQueue = DispatchQueue(label: "clickcherry.mcp.stdio.parse")
    private let stateLock = NSLock()
    private var framer = MCPMessageFramer()
    private var didSignalDisconnect = false

    var onMessage: MessageHandler?
    var onDisconnect: DisconnectHandler?
    var onStderr: TextHandler?

    private(set) var resolvedExecutablePath: String?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func start(definition: MCPServerDefinition) throws {
        let resolvedExecutable = try Self.resolveExecutable(
            definition.command,
            environment: ProcessInfo.processInfo.environment,
            fileManager: fileManager
        )
        resolvedExecutablePath = resolvedExecutable

        process.executableURL = URL(fileURLWithPath: resolvedExecutable)
        process.arguments = definition.args
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var environment = ProcessInfo.processInfo.environment
        definition.environment.forEach { key, value in
            environment[key] = value
        }
        process.environment = environment
        process.terminationHandler = { [weak self] process in
            self?.signalDisconnect(reason: "Process exited with status \(process.terminationStatus).")
        }

        installReadHandlers()

        do {
            try process.run()
        } catch {
            removeReadHandlers()
            throw MCPRuntimeError.serverFailedToStart(error.localizedDescription)
        }
    }

    func send(_ payload: Data) throws {
        guard process.isRunning else {
            throw MCPRuntimeError.processNotStarted(resolvedExecutablePath ?? "unknown")
        }
        let framed = MCPMessageFramer.frame(payload)
        try stdinPipe.fileHandleForWriting.write(contentsOf: framed)
    }

    func stop() {
        removeReadHandlers()
        if process.isRunning {
            process.terminate()
        }
        signalDisconnect(reason: "Transport stopped.")
    }

    private func installReadHandlers() {
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty {
                self.signalDisconnect(reason: "EOF from MCP server stdout.")
                return
            }

            self.parseQueue.async { [weak self] in
                guard let self else { return }
                do {
                    let messages = try self.framer.append(data)
                    for message in messages {
                        self.onMessage?(message)
                    }
                } catch {
                    self.signalDisconnect(reason: "Failed to parse MCP stdout: \(error.localizedDescription)")
                }
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            guard !text.isEmpty else { return }
            self.onStderr?(text)
        }
    }

    private func removeReadHandlers() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
    }

    private func signalDisconnect(reason: String) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !didSignalDisconnect else { return }
        didSignalDisconnect = true
        removeReadHandlers()
        onDisconnect?(reason)
    }

    private static func resolveExecutable(
        _ raw: String,
        environment: [String: String],
        fileManager: FileManager
    ) throws -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw MCPRuntimeError.executableNotFound(raw)
        }

        if cleaned.hasPrefix("/") {
            guard fileManager.isExecutableFile(atPath: cleaned) else {
                throw MCPRuntimeError.executableNotFound(cleaned)
            }
            return cleaned
        }

        let searchPaths = (environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":")
            .map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]

        for directory in Set(searchPaths) {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(cleaned, isDirectory: false)
                .path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        throw MCPRuntimeError.executableNotFound(cleaned)
    }
}
