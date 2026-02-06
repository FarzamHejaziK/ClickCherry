import Foundation
import Observation

@Observable
final class MainShellStateStore {
    private let taskService: TaskService
    private let captureService: any RecordingCaptureService

    var tasks: [TaskRecord]
    var selectedTaskID: String?
    var newTaskTitle: String
    var heartbeatMarkdown: String
    var recordings: [RecordingRecord]
    var isCapturing: Bool
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
        self.isCapturing = false
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

        do {
            let outputURL = try taskService.makeCaptureOutputURL(taskId: selectedTaskID)
            try captureService.startCapture(outputURL: outputURL)
            isCapturing = true
            recordingStatusMessage = "Capture started."
            errorMessage = nil
        } catch RecordingCaptureError.permissionDenied {
            errorMessage = "Screen Recording permission denied. Grant access in System Settings and retry."
        } catch RecordingCaptureError.alreadyCapturing {
            errorMessage = "Capture is already running."
        } catch {
            errorMessage = "Failed to start capture."
        }
    }

    func stopCapture() {
        do {
            try captureService.stopCapture()
            isCapturing = false
            loadSelectedTaskRecordings()
            recordingStatusMessage = "Capture stopped."
            errorMessage = nil
        } catch RecordingCaptureError.notCapturing {
            errorMessage = "No active capture to stop."
        } catch {
            errorMessage = "Failed to stop capture."
        }
    }
}
