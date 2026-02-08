import Foundation
import Observation
import AppKit

@Observable
final class MainShellStateStore {
    private let taskService: TaskService
    private let taskExtractionService: TaskExtractionService
    private let heartbeatQuestionService: HeartbeatQuestionService
    private let apiKeyStore: any APIKeyStore
    private let captureService: any RecordingCaptureService
    private let overlayService: any RecordingOverlayService

    var tasks: [TaskRecord]
    var selectedTaskID: String?
    var providerSetupState: ProviderSetupState
    var newTaskTitle: String
    var heartbeatMarkdown: String
    var clarificationQuestions: [HeartbeatQuestion]
    var selectedClarificationQuestionID: String?
    var clarificationAnswerDraft: String
    var recordings: [RecordingRecord]
    var availableCaptureDisplays: [CaptureDisplayOption]
    var availableCaptureAudioInputs: [CaptureAudioInputOption]
    var selectedCaptureDisplayID: Int?
    var selectedCaptureAudioInputID: String?
    var isCapturing: Bool
    var captureStartedAt: Date?
    var isExtractingTask: Bool
    var extractingRecordingID: String?
    var saveStatusMessage: String?
    var recordingStatusMessage: String?
    var extractionStatusMessage: String?
    var clarificationStatusMessage: String?
    var apiKeyStatusMessage: String?
    var apiKeyErrorMessage: String?
    var errorMessage: String?

    init(
        taskService: TaskService = TaskService(),
        taskExtractionService: TaskExtractionService? = nil,
        heartbeatQuestionService: HeartbeatQuestionService = HeartbeatQuestionService(),
        apiKeyStore: any APIKeyStore = KeychainAPIKeyStore(),
        captureService: any RecordingCaptureService = ShellRecordingCaptureService(),
        overlayService: any RecordingOverlayService = ScreenRecordingOverlayService()
    ) {
        self.taskService = taskService
        self.apiKeyStore = apiKeyStore
        self.taskExtractionService = taskExtractionService ?? TaskExtractionService(
            llmClient: GeminiVideoLLMClient(apiKeyStore: apiKeyStore)
        )
        self.heartbeatQuestionService = heartbeatQuestionService
        self.captureService = captureService
        self.overlayService = overlayService
        self.tasks = []
        self.selectedTaskID = nil
        self.providerSetupState = ProviderSetupState(
            hasOpenAIKey: apiKeyStore.hasKey(for: .openAI),
            hasAnthropicKey: apiKeyStore.hasKey(for: .anthropic),
            hasGeminiKey: apiKeyStore.hasKey(for: .gemini)
        )
        self.newTaskTitle = ""
        self.heartbeatMarkdown = ""
        self.clarificationQuestions = []
        self.selectedClarificationQuestionID = nil
        self.clarificationAnswerDraft = ""
        self.recordings = []
        self.availableCaptureDisplays = []
        self.availableCaptureAudioInputs = []
        self.selectedCaptureDisplayID = nil
        self.selectedCaptureAudioInputID = nil
        self.isCapturing = false
        self.captureStartedAt = nil
        self.isExtractingTask = false
        self.extractingRecordingID = nil
        self.saveStatusMessage = nil
        self.recordingStatusMessage = nil
        self.extractionStatusMessage = nil
        self.clarificationStatusMessage = nil
        self.apiKeyStatusMessage = nil
        self.apiKeyErrorMessage = nil
        self.errorMessage = nil
    }

    deinit {
        overlayService.hideBorder()
    }

    var selectedTask: TaskRecord? {
        guard let selectedTaskID else {
            return nil
        }
        return tasks.first(where: { $0.id == selectedTaskID })
    }

    var unresolvedClarificationQuestions: [HeartbeatQuestion] {
        clarificationQuestions.filter { !$0.isResolved }
    }

    var resolvedClarificationQuestions: [HeartbeatQuestion] {
        clarificationQuestions.filter { $0.isResolved }
    }

    var selectedClarificationQuestion: HeartbeatQuestion? {
        guard let selectedClarificationQuestionID else {
            return nil
        }
        return clarificationQuestions.first(where: { $0.id == selectedClarificationQuestionID })
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
            refreshCaptureAudioInputs()
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

    func refreshProviderKeysState() {
        providerSetupState = ProviderSetupState(
            hasOpenAIKey: apiKeyStore.hasKey(for: .openAI),
            hasAnthropicKey: apiKeyStore.hasKey(for: .anthropic),
            hasGeminiKey: apiKeyStore.hasKey(for: .gemini)
        )
    }

    @discardableResult
    func saveProviderKey(_ rawKey: String, for provider: ProviderIdentifier) -> Bool {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            apiKeyStatusMessage = nil
            apiKeyErrorMessage = "API key cannot be empty."
            return false
        }

        do {
            try apiKeyStore.setKey(key, for: provider)
            updateProviderSetupState(saved: true, for: provider)
            apiKeyStatusMessage = "Saved \(providerDisplayName(provider)) API key."
            apiKeyErrorMessage = nil
            return true
        } catch {
            apiKeyStatusMessage = nil
            apiKeyErrorMessage = "Failed to save \(providerDisplayName(provider)) API key."
            return false
        }
    }

    func clearProviderKey(for provider: ProviderIdentifier) {
        do {
            try apiKeyStore.setKey(nil, for: provider)
            updateProviderSetupState(saved: false, for: provider)
            apiKeyStatusMessage = "Removed \(providerDisplayName(provider)) API key."
            apiKeyErrorMessage = nil
        } catch {
            apiKeyStatusMessage = nil
            apiKeyErrorMessage = "Failed to remove \(providerDisplayName(provider)) API key."
        }
    }

    func selectTask(_ taskID: String?) {
        selectedTaskID = taskID
        clarificationAnswerDraft = ""
        clarificationStatusMessage = nil
        loadSelectedTaskHeartbeat()
        loadSelectedTaskRecordings()
    }

    func loadSelectedTaskHeartbeat() {
        guard let selectedTaskID else {
            heartbeatMarkdown = ""
            clarificationQuestions = []
            selectedClarificationQuestionID = nil
            clarificationAnswerDraft = ""
            return
        }

        do {
            heartbeatMarkdown = try taskService.readHeartbeat(taskId: selectedTaskID)
            saveStatusMessage = nil
            refreshClarificationQuestions()
        } catch {
            heartbeatMarkdown = ""
            clarificationQuestions = []
            selectedClarificationQuestionID = nil
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

    func refreshCaptureAudioInputs() {
        let inputs = captureService.listAudioInputs()
        availableCaptureAudioInputs = inputs
        if let selectedCaptureAudioInputID,
           inputs.contains(where: { $0.id == selectedCaptureAudioInputID }) {
            return
        }
        selectedCaptureAudioInputID = inputs.first?.id
    }

    private var selectedAudioInputMode: CaptureAudioInputMode {
        guard
            let selectedCaptureAudioInputID,
            let selected = availableCaptureAudioInputs.first(where: { $0.id == selectedCaptureAudioInputID })
        else {
            return .systemDefault
        }
        return selected.mode
    }

    private var selectedAudioInputLabel: String {
        guard
            let selectedCaptureAudioInputID,
            let selected = availableCaptureAudioInputs.first(where: { $0.id == selectedCaptureAudioInputID })
        else {
            return "System Default Microphone"
        }
        return selected.label
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

    func refreshClarificationQuestions() {
        clarificationQuestions = heartbeatQuestionService.parseQuestions(from: heartbeatMarkdown)
        if let selectedClarificationQuestionID,
           clarificationQuestions.contains(where: { $0.id == selectedClarificationQuestionID }) {
            return
        }
        selectedClarificationQuestionID = unresolvedClarificationQuestions.first?.id
            ?? clarificationQuestions.first?.id
    }

    func selectClarificationQuestion(_ questionID: String?) {
        selectedClarificationQuestionID = questionID
        clarificationAnswerDraft = ""
        clarificationStatusMessage = nil
    }

    func applyClarificationAnswer() {
        guard let selectedTaskID else {
            return
        }
        guard let selectedClarificationQuestionID else {
            errorMessage = "Select a clarification question first."
            clarificationStatusMessage = nil
            return
        }

        do {
            let updated = try heartbeatQuestionService.applyAnswer(
                clarificationAnswerDraft,
                to: selectedClarificationQuestionID,
                in: heartbeatMarkdown
            )
            try taskService.saveHeartbeat(taskId: selectedTaskID, markdown: updated)
            heartbeatMarkdown = updated
            clarificationAnswerDraft = ""
            clarificationStatusMessage = "Applied clarification answer."
            saveStatusMessage = "Saved."
            errorMessage = nil
            refreshClarificationQuestions()
        } catch HeartbeatQuestionServiceError.answerEmpty {
            clarificationStatusMessage = nil
            errorMessage = "Clarification answer cannot be empty."
        } catch HeartbeatQuestionServiceError.questionsSectionMissing {
            clarificationStatusMessage = nil
            errorMessage = "Could not find a '## Questions' section in HEARTBEAT.md."
        } catch HeartbeatQuestionServiceError.questionNotFound {
            clarificationStatusMessage = nil
            errorMessage = "The selected clarification question no longer exists."
            refreshClarificationQuestions()
        } catch {
            clarificationStatusMessage = nil
            errorMessage = "Failed to apply clarification answer."
        }
    }

    func extractTask(from recording: RecordingRecord) async {
        guard let selectedTaskID else {
            return
        }
        guard !isExtractingTask else {
            return
        }

        isExtractingTask = true
        extractingRecordingID = recording.id
        extractionStatusMessage = "Extracting task from \(recording.fileName)..."
        errorMessage = nil

        do {
            let result = try await taskExtractionService.extractHeartbeatMarkdown(from: recording.fileURL)
            if result.taskDetected {
                try taskService.saveHeartbeat(taskId: selectedTaskID, markdown: result.heartbeatMarkdown)
                loadSelectedTaskHeartbeat()
                extractionStatusMessage = "Extraction complete (\(result.llm), \(result.promptVersion))."
            } else {
                extractionStatusMessage = "No actionable task detected. HEARTBEAT.md was not changed (\(result.llm), \(result.promptVersion))."
            }
            errorMessage = nil
        } catch TaskExtractionServiceError.invalidModelOutput {
            extractionStatusMessage = nil
            errorMessage = "Extraction output was invalid. HEARTBEAT.md was not changed."
        } catch let error as GeminiLLMClientError {
            extractionStatusMessage = nil
            errorMessage = error.errorDescription ?? "Gemini request failed."
        } catch LLMClientError.notConfigured {
            extractionStatusMessage = nil
            errorMessage = "Task extraction LLM client is not configured yet."
        } catch {
            extractionStatusMessage = nil
            errorMessage = "Failed to extract task from recording."
        }

        isExtractingTask = false
        extractingRecordingID = nil
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
            refreshCaptureAudioInputs()
            let outputURL = try taskService.makeCaptureOutputURL(taskId: selectedTaskID)
            let requestedAudioInput = selectedAudioInputMode
            try captureService.startCapture(
                outputURL: outputURL,
                displayID: selectedCaptureDisplayID,
                audioInput: requestedAudioInput
            )
            isCapturing = true
            captureStartedAt = Date()
            overlayService.showBorder(displayID: selectedCaptureDisplayID)
            if captureService.lastCaptureIncludesMicrophone,
               let warning = captureService.lastCaptureStartWarning {
                recordingStatusMessage = "Capture started on Display \(selectedCaptureDisplayID) with microphone audio. \(warning)"
            } else if captureService.lastCaptureIncludesMicrophone {
                recordingStatusMessage = "Capture started on Display \(selectedCaptureDisplayID) with audio input: \(selectedAudioInputLabel)."
            } else if let warning = captureService.lastCaptureStartWarning {
                recordingStatusMessage = "Capture started on Display \(selectedCaptureDisplayID) without microphone audio. \(warning)"
            } else if requestedAudioInput == .none {
                recordingStatusMessage = "Capture started on Display \(selectedCaptureDisplayID) without microphone audio."
            } else {
                recordingStatusMessage = "Capture started on Display \(selectedCaptureDisplayID)."
            }
            errorMessage = nil
        } catch RecordingCaptureError.permissionDenied {
            isCapturing = false
            captureStartedAt = nil
            overlayService.hideBorder()
            errorMessage = "Screen Recording permission denied. Grant access in System Settings and retry."
        } catch RecordingCaptureError.alreadyCapturing {
            errorMessage = "Capture is already running."
        } catch RecordingCaptureError.failedToStart(let reason) {
            isCapturing = false
            captureStartedAt = nil
            overlayService.hideBorder()
            errorMessage = "Failed to start capture: \(reason)"
        } catch {
            isCapturing = false
            captureStartedAt = nil
            overlayService.hideBorder()
            errorMessage = "Failed to start capture."
        }
    }

    func stopCapture() {
        do {
            try captureService.stopCapture()
            isCapturing = false
            captureStartedAt = nil
            overlayService.hideBorder()
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
            overlayService.hideBorder()
            errorMessage = "No active capture to stop."
        } catch RecordingCaptureError.failedToStop(let reason) {
            isCapturing = false
            captureStartedAt = nil
            overlayService.hideBorder()
            errorMessage = "Failed to stop capture: \(reason)"
        } catch {
            overlayService.hideBorder()
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

    private func updateProviderSetupState(saved: Bool, for provider: ProviderIdentifier) {
        switch provider {
        case .openAI:
            providerSetupState.hasOpenAIKey = saved
        case .anthropic:
            providerSetupState.hasAnthropicKey = saved
        case .gemini:
            providerSetupState.hasGeminiKey = saved
        }
    }

    private func providerDisplayName(_ provider: ProviderIdentifier) -> String {
        switch provider {
        case .openAI:
            return "OpenAI"
        case .anthropic:
            return "Anthropic"
        case .gemini:
            return "Gemini"
        }
    }
}
