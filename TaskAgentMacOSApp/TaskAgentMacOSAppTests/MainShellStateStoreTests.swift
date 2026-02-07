import Foundation
import Testing
@testable import TaskAgentMacOSApp

private final class MockRecordingCaptureService: RecordingCaptureService {
    var isCapturing = false
    var lastCaptureIncludesMicrophone = true
    var lastCaptureStartWarning: String?
    var shouldFailStart = false
    var shouldFailStop = false
    var shouldDenyPermission = false
    var displays: [CaptureDisplayOption] = [CaptureDisplayOption(id: 1, label: "Display 1")]
    var audioInputs: [CaptureAudioInputOption] = [
        CaptureAudioInputOption(id: "default", label: "System Default Microphone", mode: .systemDefault),
        CaptureAudioInputOption(id: "device-42", label: "Test Mic (ID 42)", mode: .device(42)),
        CaptureAudioInputOption(id: "none", label: "No Microphone", mode: .none)
    ]
    var startedOutputURL: URL?
    var startedDisplayID: Int?
    var startedAudioInput: CaptureAudioInputMode?

    func listDisplays() -> [CaptureDisplayOption] {
        displays
    }

    func listAudioInputs() -> [CaptureAudioInputOption] {
        audioInputs
    }

    func startCapture(outputURL: URL, displayID: Int, audioInput: CaptureAudioInputMode) throws {
        if shouldDenyPermission {
            throw RecordingCaptureError.permissionDenied
        }
        if shouldFailStart {
            throw RecordingCaptureError.failedToStart("mock start failure")
        }
        if isCapturing {
            throw RecordingCaptureError.alreadyCapturing
        }
        startedOutputURL = outputURL
        startedDisplayID = displayID
        startedAudioInput = audioInput
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

private final class MockRecordingOverlayService: RecordingOverlayService {
    var shownDisplayIDs: [Int] = []
    var hideCallCount = 0

    func showBorder(displayID: Int) {
        shownDisplayIDs.append(displayID)
    }

    func hideBorder() {
        hideCallCount += 1
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

        let store = MainShellStateStore(
            taskService: service,
            captureService: MockRecordingCaptureService(),
            overlayService: MockRecordingOverlayService()
        )
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

        let store = MainShellStateStore(
            taskService: service,
            captureService: MockRecordingCaptureService(),
            overlayService: MockRecordingOverlayService()
        )
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
        let overlayService = MockRecordingOverlayService()

        let store = MainShellStateStore(
            taskService: service,
            captureService: captureService,
            overlayService: overlayService
        )
        store.reloadTasks()
        store.selectTask(created.id)
        store.refreshCaptureDisplays()
        store.refreshCaptureAudioInputs()
        store.selectedCaptureAudioInputID = "device-42"

        store.startCapture()
        #expect(store.isCapturing)
        #expect(captureService.startedOutputURL != nil)
        #expect(captureService.startedDisplayID == 1)
        #expect(captureService.startedAudioInput == .device(42))
        #expect(overlayService.shownDisplayIDs == [1])

        store.stopCapture()
        #expect(!store.isCapturing)
        #expect(store.recordingStatusMessage == "Capture stopped.")
        #expect(overlayService.hideCallCount == 1)
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
        let overlayService = MockRecordingOverlayService()
        captureService.shouldDenyPermission = true

        let store = MainShellStateStore(
            taskService: service,
            captureService: captureService,
            overlayService: overlayService
        )
        store.reloadTasks()
        store.selectTask(created.id)
        store.refreshCaptureDisplays()
        store.refreshCaptureAudioInputs()
        store.startCapture()

        #expect(!store.isCapturing)
        #expect(store.errorMessage == "Screen Recording permission denied. Grant access in System Settings and retry.")
        #expect(overlayService.hideCallCount == 1)
    }
}
