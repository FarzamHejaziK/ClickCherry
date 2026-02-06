import Foundation
import Testing
@testable import TaskAgentMacOSApp

private final class MockRecordingCaptureService: RecordingCaptureService {
    var isCapturing = false
    var shouldFailStart = false
    var shouldFailStop = false
    var shouldDenyPermission = false
    var startedOutputURL: URL?

    func startCapture(outputURL: URL) throws {
        if shouldDenyPermission {
            throw RecordingCaptureError.permissionDenied
        }
        if shouldFailStart {
            throw RecordingCaptureError.failedToStart
        }
        if isCapturing {
            throw RecordingCaptureError.alreadyCapturing
        }
        startedOutputURL = outputURL
        isCapturing = true
    }

    func stopCapture() throws {
        if shouldFailStop {
            throw RecordingCaptureError.notCapturing
        }
        guard isCapturing else {
            throw RecordingCaptureError.notCapturing
        }
        isCapturing = false
    }
}

struct MainShellStateStoreTests {
    @Test
    func selectTaskLoadsHeartbeatMarkdown() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let service = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let created = try service.createTask(title: "Initial task")

        let store = MainShellStateStore(taskService: service)
        store.reloadTasks()
        store.selectTask(created.id)

        #expect(store.heartbeatMarkdown.contains("# Task"))
        #expect(store.heartbeatMarkdown.contains("Initial task"))
    }

    @Test
    func saveSelectedTaskHeartbeatPersistsContent() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let service = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let created = try service.createTask(title: "Task one")

        let store = MainShellStateStore(taskService: service)
        store.reloadTasks()
        store.selectTask(created.id)
        store.heartbeatMarkdown = """
        # Task
        Updated from store test

        ## Questions
        - None
        """
        store.saveSelectedTaskHeartbeat()

        let persisted = try service.readHeartbeat(taskId: created.id)
        #expect(persisted.contains("Updated from store test"))
        #expect(store.saveStatusMessage == "Saved.")
    }

    @Test
    func startAndStopCaptureUpdatesCaptureState() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let service = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let created = try service.createTask(title: "Capture task")
        let captureService = MockRecordingCaptureService()

        let store = MainShellStateStore(taskService: service, captureService: captureService)
        store.reloadTasks()
        store.selectTask(created.id)

        store.startCapture()
        #expect(store.isCapturing)
        #expect(captureService.startedOutputURL != nil)

        store.stopCapture()
        #expect(!store.isCapturing)
        #expect(store.recordingStatusMessage == "Capture stopped.")
    }

    @Test
    func startCaptureShowsPermissionErrorWhenDenied() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let service = TaskService(
            baseDir: tempRoot,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let created = try service.createTask(title: "Permission task")
        let captureService = MockRecordingCaptureService()
        captureService.shouldDenyPermission = true

        let store = MainShellStateStore(taskService: service, captureService: captureService)
        store.reloadTasks()
        store.selectTask(created.id)
        store.startCapture()

        #expect(!store.isCapturing)
        #expect(store.errorMessage == "Screen Recording permission denied. Grant access in System Settings and retry.")
    }
}
