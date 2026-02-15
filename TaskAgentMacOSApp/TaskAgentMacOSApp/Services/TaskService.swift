import Foundation

enum TaskServiceError: Error {
    case taskNotFound
    case invalidRecordingFormat
    case recordingTooLarge
    case runPersistenceFailed
}

struct TaskService {
    private let fileManager: FileManager
    private let workspaceService: WorkspaceService
    private let baseDir: URL
    private let agentRunLogService: AgentRunLogService

    init(
        baseDir: URL = TaskService.defaultBaseDirectory(),
        fileManager: FileManager = .default,
        workspaceService: WorkspaceService = WorkspaceService()
    ) {
        self.baseDir = baseDir
        self.fileManager = fileManager
        self.workspaceService = workspaceService
        self.agentRunLogService = AgentRunLogService(fileManager: fileManager)
    }

    func createTask(title: String) throws -> TaskRecord {
        try createBaseDirIfNeeded()

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = normalizedTitle.isEmpty ? "Untitled Task" : normalizedTitle
        let taskId = UUID().uuidString.lowercased()
        let workspace = try workspaceService.initializeWorkspace(
            baseDir: baseDir,
            taskId: taskId,
            taskTitle: finalTitle
        )

        return TaskRecord(id: taskId, title: finalTitle, createdAt: Date(), workspace: workspace)
    }

    func listTasks() throws -> [TaskRecord] {
        try createBaseDirIfNeeded()

        let entries = try fileManager.contentsOfDirectory(
            at: baseDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )

        let tasks: [TaskRecord] = entries.compactMap { url in
            guard url.hasDirectoryPath, url.lastPathComponent.hasPrefix("workspace-") else {
                return nil
            }

            let taskId = String(url.lastPathComponent.dropFirst("workspace-".count))
            let workspace = TaskWorkspace(
                taskId: taskId,
                root: url,
                heartbeatFile: url.appendingPathComponent("HEARTBEAT.md", isDirectory: false),
                recordingsDir: url.appendingPathComponent("recordings", isDirectory: true),
                runsDir: url.appendingPathComponent("runs", isDirectory: true)
            )

            guard fileManager.fileExists(atPath: workspace.heartbeatFile.path) else {
                return nil
            }

            let title = (try? readTaskTitle(from: workspace.heartbeatFile)) ?? "Untitled Task"
            let createdAt = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast

            return TaskRecord(id: taskId, title: title, createdAt: createdAt, workspace: workspace)
        }

        return tasks.sorted(by: { $0.createdAt > $1.createdAt })
    }

    func deleteTask(taskId: String) throws {
        let workspace = workspaceURL(for: taskId)
        guard fileManager.fileExists(atPath: workspace.path) else {
            throw TaskServiceError.taskNotFound
        }
        try fileManager.removeItem(at: workspace)
    }

    func readHeartbeat(taskId: String) throws -> String {
        let heartbeat = heartbeatURL(for: taskId)
        guard fileManager.fileExists(atPath: heartbeat.path) else {
            throw TaskServiceError.taskNotFound
        }

        return try String(contentsOf: heartbeat, encoding: .utf8)
    }

    func saveHeartbeat(taskId: String, markdown: String) throws {
        let heartbeat = heartbeatURL(for: taskId)
        guard fileManager.fileExists(atPath: heartbeat.path) else {
            throw TaskServiceError.taskNotFound
        }

        try markdown.write(to: heartbeat, atomically: true, encoding: .utf8)
    }

    func importRecording(taskId: String, sourceURL: URL) throws -> RecordingRecord {
        let workspace = workspaceURL(for: taskId)
        guard fileManager.fileExists(atPath: workspace.path) else {
            throw TaskServiceError.taskNotFound
        }

        guard sourceURL.pathExtension.lowercased() == "mp4" else {
            throw TaskServiceError.invalidRecordingFormat
        }

        let sourceValues = try sourceURL.resourceValues(forKeys: [.fileSizeKey])
        let sourceSize = Int64(sourceValues.fileSize ?? 0)
        let maxRecordingBytes: Int64 = 2 * 1024 * 1024 * 1024
        guard sourceSize <= maxRecordingBytes else {
            throw TaskServiceError.recordingTooLarge
        }

        let recordingsDir = recordingsURL(for: taskId)
        if !fileManager.fileExists(atPath: recordingsDir.path) {
            try fileManager.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        }

        let destinationName = "\(Int(Date().timeIntervalSince1970))-\(sourceURL.lastPathComponent)"
        let destinationURL = recordingsDir.appendingPathComponent(destinationName, isDirectory: false)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let addedValues = try destinationURL.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
        return RecordingRecord(
            id: destinationName,
            fileName: destinationName,
            addedAt: addedValues.creationDate ?? Date(),
            fileURL: destinationURL,
            fileSizeBytes: Int64(addedValues.fileSize ?? 0)
        )
    }

    func listRecordings(taskId: String) throws -> [RecordingRecord] {
        let recordingsDir = recordingsURL(for: taskId)
        guard fileManager.fileExists(atPath: recordingsDir.path) else {
            return []
        }

        let entries = try fileManager.contentsOfDirectory(
            at: recordingsDir,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        let records = entries.compactMap { url -> RecordingRecord? in
            let ext = url.pathExtension.lowercased()
            guard ext == "mp4" || ext == "mov" else {
                return nil
            }

            let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            return RecordingRecord(
                id: url.lastPathComponent,
                fileName: url.lastPathComponent,
                addedAt: values?.creationDate ?? Date.distantPast,
                fileURL: url,
                fileSizeBytes: Int64(values?.fileSize ?? 0)
            )
        }

        return records.sorted(by: { $0.addedAt > $1.addedAt })
    }

    func makeCaptureOutputURL(taskId: String) throws -> URL {
        let workspace = workspaceURL(for: taskId)
        guard fileManager.fileExists(atPath: workspace.path) else {
            throw TaskServiceError.taskNotFound
        }

        let recordingsDir = recordingsURL(for: taskId)
        if !fileManager.fileExists(atPath: recordingsDir.path) {
            try fileManager.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let suffix = UUID().uuidString.prefix(8).lowercased()
        return recordingsDir.appendingPathComponent("capture-\(timestamp)-\(suffix).mov", isDirectory: false)
    }

    /// Attach a recording file (captured `.mov` or imported `.mp4`) to a task.
    /// For `.mov` (capture staging) we prefer deleting the source after copying.
    func attachRecordingFile(taskId: String, sourceURL: URL, deleteSourceAfterCopy: Bool) throws -> RecordingRecord {
        let workspace = workspaceURL(for: taskId)
        guard fileManager.fileExists(atPath: workspace.path) else {
            throw TaskServiceError.taskNotFound
        }

        let ext = sourceURL.pathExtension.lowercased()
        guard ext == "mp4" || ext == "mov" else {
            throw TaskServiceError.invalidRecordingFormat
        }

        let sourceValues = try sourceURL.resourceValues(forKeys: [.fileSizeKey])
        let sourceSize = Int64(sourceValues.fileSize ?? 0)
        let maxRecordingBytes: Int64 = 2 * 1024 * 1024 * 1024
        guard sourceSize <= maxRecordingBytes else {
            throw TaskServiceError.recordingTooLarge
        }

        let recordingsDir = recordingsURL(for: taskId)
        if !fileManager.fileExists(atPath: recordingsDir.path) {
            try fileManager.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        }

        let destinationName = "\(Int(Date().timeIntervalSince1970))-\(sourceURL.lastPathComponent)"
        let destinationURL = recordingsDir.appendingPathComponent(destinationName, isDirectory: false)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        if deleteSourceAfterCopy {
            try? fileManager.removeItem(at: sourceURL)
        }

        let addedValues = try destinationURL.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
        return RecordingRecord(
            id: destinationName,
            fileName: destinationName,
            addedAt: addedValues.creationDate ?? Date(),
            fileURL: destinationURL,
            fileSizeBytes: Int64(addedValues.fileSize ?? 0)
        )
    }

    /// Output location used for New Task recording before a task exists.
    /// This is deleted if the user dismisses the post-recording dialog without extracting.
    func makeStagingCaptureOutputURL() throws -> URL {
        try createBaseDirIfNeeded()

        let stagingDir = baseDir.appendingPathComponent(".staging", isDirectory: true)
        if !fileManager.fileExists(atPath: stagingDir.path) {
            try fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let suffix = UUID().uuidString.prefix(8).lowercased()
        return stagingDir.appendingPathComponent("capture-\(timestamp)-\(suffix).mov", isDirectory: false)
    }

    @discardableResult
    func saveRunSummary(taskId: String, summary: AutomationRunSummary) throws -> URL {
        let workspace = workspaceURL(for: taskId)
        guard fileManager.fileExists(atPath: workspace.path) else {
            throw TaskServiceError.taskNotFound
        }

        let runsDir = workspace.appendingPathComponent("runs", isDirectory: true)
        if !fileManager.fileExists(atPath: runsDir.path) {
            try fileManager.createDirectory(at: runsDir, withIntermediateDirectories: true)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: summary.startedAt).replacingOccurrences(of: ":", with: "-")
        let fileURL = runsDir.appendingPathComponent(
            "run-\(timestamp)-\(UUID().uuidString.prefix(8).lowercased()).md",
            isDirectory: false
        )

        var lines: [String] = []
        lines.append("# Run Summary")
        lines.append("")
        lines.append("StartedAt: \(formatter.string(from: summary.startedAt))")
        lines.append("FinishedAt: \(formatter.string(from: summary.finishedAt))")
        lines.append("Outcome: \(outcomeDescription(summary.outcome))")
        if let errorMessage = summary.errorMessage, !errorMessage.isEmpty {
            lines.append("Error: \(errorMessage)")
        }
        if let llmSummary = summary.llmSummary, !llmSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("## LLM Summary")
            lines.append(llmSummary.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        lines.append("")
        lines.append("## Executed Steps")
        if summary.executedSteps.isEmpty {
            lines.append("- None.")
        } else {
            for step in summary.executedSteps {
                lines.append("- \(step)")
            }
        }
        lines.append("")
        lines.append("## Generated Questions")
        if summary.generatedQuestions.isEmpty {
            lines.append("- None.")
        } else {
            for question in summary.generatedQuestions {
                lines.append("- \(question)")
            }
        }
        lines.append("")

        let markdown = lines.joined(separator: "\n")
        do {
            try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            throw TaskServiceError.runPersistenceFailed
        }
    }

    @discardableResult
    func saveAgentRunLog(taskId: String, run: AgentRunRecord) throws -> URL {
        let workspace = workspaceURL(for: taskId)
        guard fileManager.fileExists(atPath: workspace.path) else {
            throw TaskServiceError.taskNotFound
        }

        let runsDir = workspace.appendingPathComponent("runs", isDirectory: true)
        return try agentRunLogService.persist(run: run, runsDir: runsDir)
    }

    func listAgentRunLogs(taskId: String) throws -> [AgentRunRecord] {
        let workspace = workspaceURL(for: taskId)
        guard fileManager.fileExists(atPath: workspace.path) else {
            throw TaskServiceError.taskNotFound
        }

        let runsDir = workspace.appendingPathComponent("runs", isDirectory: true)
        return try agentRunLogService.listRuns(runsDir: runsDir)
    }

    private func readTaskTitle(from heartbeatFile: URL) throws -> String {
        let markdown = try String(contentsOf: heartbeatFile, encoding: .utf8)
        let lines = markdown.components(separatedBy: .newlines)

        guard let taskHeaderIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "# Task" }) else {
            return "Untitled Task"
        }

        guard taskHeaderIndex + 1 < lines.count else {
            return "Untitled Task"
        }

        for line in lines[(taskHeaderIndex + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            if trimmed.hasPrefix("## ") {
                break
            }
            return trimmed
        }

        return "Untitled Task"
    }

    private func createBaseDirIfNeeded() throws {
        if !fileManager.fileExists(atPath: baseDir.path) {
            try fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
        }
    }

    private static func defaultBaseDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("TaskAgentMacOS", isDirectory: true)
    }

    private func heartbeatURL(for taskId: String) -> URL {
        workspaceURL(for: taskId)
            .appendingPathComponent("HEARTBEAT.md", isDirectory: false)
    }

    private func recordingsURL(for taskId: String) -> URL {
        workspaceURL(for: taskId)
            .appendingPathComponent("recordings", isDirectory: true)
    }

    private func workspaceURL(for taskId: String) -> URL {
        baseDir.appendingPathComponent("workspace-\(taskId)", isDirectory: true)
    }

    private func outcomeDescription(_ outcome: AutomationRunOutcome) -> String {
        switch outcome {
        case .success:
            return "SUCCESS"
        case .needsClarification:
            return "NEEDS_CLARIFICATION"
        case .failed:
            return "FAILED"
        case .cancelled:
            return "CANCELLED"
        }
    }
}

private struct AgentRunLogFileV1: Codable {
    var version: Int
    var run: AgentRunRecord
}

private struct AgentRunLogService {
    private let fileManager: FileManager

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    @discardableResult
    func persist(run: AgentRunRecord, runsDir: URL) throws -> URL {
        if !fileManager.fileExists(atPath: runsDir.path) {
            try fileManager.createDirectory(at: runsDir, withIntermediateDirectories: true)
        }

        let timestamp = Self.isoTimestamp(for: run.startedAt).replacingOccurrences(of: ":", with: "-")
        let suffix = run.id.uuidString.prefix(8).lowercased()
        let fileURL = runsDir.appendingPathComponent("agent-run-\(timestamp)-\(suffix).json", isDirectory: false)

        let payload = AgentRunLogFileV1(version: 1, run: run)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.isoTimestamp(for: date))
        }

        do {
            let data = try encoder.encode(payload)
            try data.write(to: fileURL, options: [.atomic])
            return fileURL
        } catch {
            throw TaskServiceError.runPersistenceFailed
        }
    }

    func listRuns(runsDir: URL) throws -> [AgentRunRecord] {
        guard fileManager.fileExists(atPath: runsDir.path) else {
            return []
        }

        let urls = try fileManager.contentsOfDirectory(
            at: runsDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )

        let candidates = urls.filter { $0.lastPathComponent.hasPrefix("agent-run-") && $0.pathExtension.lowercased() == "json" }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = Self.parseISO(str) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(str)")
        }

        var runs: [AgentRunRecord] = []
        for url in candidates {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let decoded = try? decoder.decode(AgentRunLogFileV1.self, from: data) {
                runs.append(decoded.run)
            }
        }

        // Newest first in the UI.
        return runs.sorted(by: { $0.startedAt > $1.startedAt })
    }

    private static func isoTimestamp(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func parseISO(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
