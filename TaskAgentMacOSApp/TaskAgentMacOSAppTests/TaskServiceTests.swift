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
}
