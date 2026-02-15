import Foundation
import Testing
@testable import TaskAgentMacOSApp

struct TaskServiceTests {
    @Test
    func createTaskCreatesWorkspaceAndHeartbeatWithTitle() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )

        let task = try taskService.createTask(title: "Prepare weekly report")

        #expect(fm.fileExists(atPath: task.workspace.root.path))
        #expect(fm.fileExists(atPath: task.workspace.heartbeatFile.path))
        let heartbeat = try String(contentsOf: task.workspace.heartbeatFile, encoding: .utf8)
        #expect(heartbeat.contains("# Task"))
        #expect(heartbeat.contains("Prepare weekly report"))
        #expect(heartbeat.contains("## Questions"))
    }

    @Test
    func listTasksReturnsCreatedTasksAndParsesTitles() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )

        _ = try taskService.createTask(title: "Task A")
        _ = try taskService.createTask(title: "Task B")

        let listed = try taskService.listTasks()
        #expect(listed.count == 2)
        #expect(Set(listed.map(\.title)) == Set(["Task A", "Task B"]))
        #expect(listed.allSatisfy { fm.fileExists(atPath: $0.workspace.heartbeatFile.path) })
    }

    @Test
    func createTaskUsesUntitledWhenInputIsBlank() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )

        let created = try taskService.createTask(title: "   ")
        #expect(created.title == "Untitled Task")
    }

    @Test
    func readAndSaveHeartbeatPersistsMarkdownChanges() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )

        let task = try taskService.createTask(title: "Draft email")
        let updated = """
        # Task
        Draft monthly email summary

        ## Questions
        - Who is the audience?
        """

        try taskService.saveHeartbeat(taskId: task.id, markdown: updated)
        let readBack = try taskService.readHeartbeat(taskId: task.id)
        #expect(readBack == updated)

        let tasks = try taskService.listTasks()
        let refreshed = try #require(tasks.first(where: { $0.id == task.id }))
        #expect(refreshed.title == "Draft monthly email summary")
    }

    @Test
    func importRecordingCopiesMp4IntoTaskRecordings() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )

        let task = try taskService.createTask(title: "Import test")
        let sourceFile = tempRoot.appendingPathComponent("sample.mp4", isDirectory: false)
        try Data("fake video bytes".utf8).write(to: sourceFile)

        _ = try taskService.importRecording(taskId: task.id, sourceURL: sourceFile)
        let recordings = try taskService.listRecordings(taskId: task.id)

        #expect(recordings.count == 1)
        #expect(recordings[0].fileName.hasSuffix(".mp4"))
        #expect(fm.fileExists(atPath: recordings[0].fileURL.path))
    }

    @Test
    func importRecordingRejectsNonMp4File() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )

        let task = try taskService.createTask(title: "Import test")
        let sourceFile = tempRoot.appendingPathComponent("not-video.txt", isDirectory: false)
        try Data("text".utf8).write(to: sourceFile)

        do {
            _ = try taskService.importRecording(taskId: task.id, sourceURL: sourceFile)
            #expect(Bool(false))
        } catch {
            #expect(error as? TaskServiceError == .invalidRecordingFormat)
        }
    }

    @Test
    func makeCaptureOutputURLTargetsTaskRecordingsDir() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let task = try taskService.createTask(title: "Capture URL task")

        let outputURL = try taskService.makeCaptureOutputURL(taskId: task.id)
        #expect(outputURL.path.contains("/workspace-\(task.id)/recordings/"))
        #expect(outputURL.pathExtension.lowercased() == "mov")
    }

    @Test
    func listRecordingsIncludesMovFiles() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let task = try taskService.createTask(title: "Mov listing task")
        let outputURL = try taskService.makeCaptureOutputURL(taskId: task.id)
        try Data("mov data".utf8).write(to: outputURL)

        let recordings = try taskService.listRecordings(taskId: task.id)
        #expect(recordings.count == 1)
        #expect(recordings[0].fileName.hasSuffix(".mov"))
    }

    @Test
    func saveRunSummaryWritesRunArtifact() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let task = try taskService.createTask(title: "Run artifact task")
        let now = Date()
        let summary = AutomationRunSummary(
            startedAt: now,
            finishedAt: now.addingTimeInterval(1),
            outcome: .needsClarification,
            executedSteps: ["Open app 'Google Chrome'"],
            generatedQuestions: ["Which profile should I use?"],
            errorMessage: "Execution paused.",
            llmSummary: "Paused for clarification."
        )

        let fileURL = try taskService.saveRunSummary(taskId: task.id, summary: summary)
        let markdown = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(fm.fileExists(atPath: fileURL.path))
        #expect(markdown.contains("# Run Summary"))
        #expect(markdown.contains("Outcome: NEEDS_CLARIFICATION"))
        #expect(markdown.contains("## LLM Summary"))
        #expect(markdown.contains("## Generated Questions"))
    }

    @Test
    func saveAndListAgentRunLogsRoundTrips() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let task = try taskService.createTask(title: "Run log task")

        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let finished = started.addingTimeInterval(2)
        let run = AgentRunRecord(
            id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
            startedAt: started,
            finishedAt: finished,
            outcome: .success,
            displayIndex: 2,
            events: [
                AgentRunEvent(
                    id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                    timestamp: started,
                    kind: .info,
                    message: "Run started"
                ),
                AgentRunEvent(
                    id: UUID(uuidString: "66666666-7777-8888-9999-000000000000")!,
                    timestamp: finished,
                    kind: .completion,
                    message: "Run finished"
                )
            ]
        )

        let url = try taskService.saveAgentRunLog(taskId: task.id, run: run)
        #expect(fm.fileExists(atPath: url.path))

        let listed = try taskService.listAgentRunLogs(taskId: task.id)
        #expect(listed.count == 1)
        #expect(listed[0] == run)
    }

    @Test
    func deleteTaskRemovesWorkspace() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let taskService = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )

        let task = try taskService.createTask(title: "Delete me")
        #expect(fm.fileExists(atPath: task.workspace.root.path))

        try taskService.deleteTask(taskId: task.id)
        #expect(!fm.fileExists(atPath: task.workspace.root.path))

        let listed = try taskService.listTasks()
        #expect(listed.isEmpty)
    }
}
