import Foundation
import Observation
import AppKit

@Observable
final class MainShellStateStore {
    private let taskService: TaskService
    private let captureService: any RecordingCaptureService

    var tasks: [TaskRecord]
    var selectedTaskID: String?
    var newTaskTitle: String
    var heartbeatMarkdown: String
    var recordings: [RecordingRecord]
    var availableCaptureDisplays: [CaptureDisplayOption]
    var selectedCaptureDisplayID: Int?
    var isCapturing: Bool
    var captureStartedAt: Date?
    var saveStatusMessage: String?
    var recordingStatusMessage: String?
    var errorMessage: String?

    init(
        taskService: TaskService = TaskService(),
        captureService: any RecordingCaptureService = ShellRecordingCaptureService()
    ) {
        self.taskService = taskService
        self.captureService = captureService
        self.tasks = []
        self.selectedTaskID = nil
        self.newTaskTitle = ""
        self.heartbeatMarkdown = ""
        self.recordings = []
        self.availableCaptureDisplays = []
        self.selectedCaptureDisplayID = nil
        self.isCapturing = false
        self.captureStartedAt = nil
        self.saveStatusMessage = nil
        self.recordingStatusMessage = nil
        self.errorMessage = nil
    }

    var selectedTask: TaskRecord? {
        guard let selectedTaskID else {
            return nil
        }
        return tasks.first(where: { $0.id == selectedTaskID })
    }

    func reloadTasks() {
        do {
            tasks = try taskService.listTasks()
            if selectedTaskID == nil {
                selectedTaskID = tasks.first?.id
            } else if selectedTask == nil {
                selectedTaskID = tasks.first?.id
            }
            loadSelectedTaskHeartbeat()
            loadSelectedTaskRecordings()
            refreshCaptureDisplays()
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load tasks."
        }
    }

    func createTask() {
        do {
            let created = try taskService.createTask(title: newTaskTitle)
            newTaskTitle = ""
            reloadTasks()
            selectedTaskID = created.id
            loadSelectedTaskHeartbeat()
            loadSelectedTaskRecordings()
            errorMessage = nil
        } catch {
            errorMessage = "Failed to create task."
        }
    }

    func selectTask(_ taskID: String?) {
        selectedTaskID = taskID
        loadSelectedTaskHeartbeat()
        loadSelectedTaskRecordings()
    }

    func loadSelectedTaskHeartbeat() {
        guard let selectedTaskID else {
            heartbeatMarkdown = ""
            return
        }

        do {
            heartbeatMarkdown = try taskService.readHeartbeat(taskId: selectedTaskID)
            saveStatusMessage = nil
        } catch {
            heartbeatMarkdown = ""
            errorMessage = "Failed to load HEARTBEAT.md."
        }
    }

    func loadSelectedTaskRecordings() {
        guard let selectedTaskID else {
            recordings = []
            return
        }

        do {
            recordings = try taskService.listRecordings(taskId: selectedTaskID)
            recordingStatusMessage = nil
        } catch {
            recordings = []
            errorMessage = "Failed to load recordings."
        }
    }

    func refreshCaptureDisplays() {
        let displays = captureService.listDisplays()
        availableCaptureDisplays = displays
        if let selectedCaptureDisplayID,
           displays.contains(where: { $0.id == selectedCaptureDisplayID }) {
            return
        }
        selectedCaptureDisplayID = displays.first?.id
    }

    func saveSelectedTaskHeartbeat() {
        guard let selectedTaskID else {
            return
        }

        do {
            try taskService.saveHeartbeat(taskId: selectedTaskID, markdown: heartbeatMarkdown)
            reloadTasks()
            self.selectedTaskID = selectedTaskID
            loadSelectedTaskHeartbeat()
            saveStatusMessage = "Saved."
            errorMessage = nil
        } catch {
            saveStatusMessage = nil
            errorMessage = "Failed to save HEARTBEAT.md."
        }
    }

    func importRecording(from sourceURL: URL) {
        guard let selectedTaskID else {
            return
        }

        do {
            _ = try taskService.importRecording(taskId: selectedTaskID, sourceURL: sourceURL)
            loadSelectedTaskRecordings()
            recordingStatusMessage = "Recording imported."
            errorMessage = nil
        } catch TaskServiceError.invalidRecordingFormat {
            recordingStatusMessage = nil
            errorMessage = "Only .mp4 files are supported."
        } catch TaskServiceError.recordingTooLarge {
            recordingStatusMessage = nil
            errorMessage = "Recording exceeds 2 GB limit."
        } catch {
            recordingStatusMessage = nil
            errorMessage = "Failed to import recording."
        }
    }

    func startCapture() {
        guard let selectedTaskID else {
            return
        }
        guard let selectedCaptureDisplayID else {
            errorMessage = "No display detected for capture."
            return
        }

        do {
            let outputURL = try taskService.makeCaptureOutputURL(taskId: selectedTaskID)
            try captureService.startCapture(outputURL: outputURL, displayID: selectedCaptureDisplayID)
            isCapturing = true
            captureStartedAt = Date()
            if captureService.lastCaptureIncludesMicrophone {
                recordingStatusMessage = "Capture started on Display \(selectedCaptureDisplayID) with microphone audio."
            } else if let warning = captureService.lastCaptureStartWarning {
                recordingStatusMessage = "Capture started on Display \(selectedCaptureDisplayID) without microphone audio. \(warning)"
            } else {
                recordingStatusMessage = "Capture started on Display \(selectedCaptureDisplayID)."
            }
            errorMessage = nil
        } catch RecordingCaptureError.permissionDenied {
            isCapturing = false
            captureStartedAt = nil
            errorMessage = "Screen Recording permission denied. Grant access in System Settings and retry."
        } catch RecordingCaptureError.alreadyCapturing {
            errorMessage = "Capture is already running."
        } catch RecordingCaptureError.failedToStart(let reason) {
            isCapturing = false
            captureStartedAt = nil
            errorMessage = "Failed to start capture: \(reason)"
        } catch {
            isCapturing = false
            captureStartedAt = nil
            errorMessage = "Failed to start capture."
        }
    }

    func stopCapture() {
        do {
            try captureService.stopCapture()
            isCapturing = false
            captureStartedAt = nil
            loadSelectedTaskRecordings()
            if let latest = recordings.first {
                recordingStatusMessage = "Capture stopped. Saved \(latest.fileName)."
            } else {
                recordingStatusMessage = "Capture stopped."
            }
            errorMessage = nil
        } catch RecordingCaptureError.notCapturing {
            isCapturing = false
            captureStartedAt = nil
            errorMessage = "No active capture to stop."
        } catch RecordingCaptureError.failedToStop(let reason) {
            isCapturing = false
            captureStartedAt = nil
            errorMessage = "Failed to stop capture: \(reason)"
        } catch {
            errorMessage = "Failed to stop capture."
        }
    }

    func revealRecordingInFinder(_ recording: RecordingRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([recording.fileURL])
    }

    func playRecording(_ recording: RecordingRecord) {
        let opened = NSWorkspace.shared.open(recording.fileURL)
        if !opened {
            errorMessage = "Failed to open recording."
        }
    }
}
