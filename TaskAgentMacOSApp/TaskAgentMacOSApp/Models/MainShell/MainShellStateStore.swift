import Foundation
import Observation
import AppKit

@Observable
final class MainShellStateStore {
    enum CaptureWindowHideMode {
        case miniaturized
        case orderedOut
    }

    struct CaptureHiddenWindow {
        let window: NSWindow
        let mode: CaptureWindowHideMode
    }

    final class LockedBox<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: Value

        init(_ value: Value) {
            self._value = value
        }

        var value: Value {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _value
            }
            set {
                lock.lock()
                _value = newValue
                lock.unlock()
            }
        }
    }

    let taskService: TaskService
    let taskExtractionService: TaskExtractionService
    let heartbeatQuestionService: HeartbeatQuestionService
    let automationEngine: any AutomationEngine
    let apiKeyStore: any APIKeyStore
    let permissionService: any PermissionService
    let captureService: any RecordingCaptureService
    let overlayService: any RecordingOverlayService
    let recordingControlOverlayService: any RecordingControlOverlayService
    let agentControlOverlayService: any AgentControlOverlayService
    let userInterruptionMonitor: any UserInterruptionMonitor
    let agentCursorPresentationService: any AgentCursorPresentationService
    let prepareDesktopForRun: @MainActor () -> Int
    let revealAppAfterRunCancellation: @MainActor () -> Void
    let llmCallRecorder: LLMCallRecorder
    let llmScreenshotRecorder: LLMScreenshotRecorder
    let executionTraceRecorder: ExecutionTraceRecorder
    let userDefaults: UserDefaults
    var runTaskHandle: Task<Void, Never>?
    @ObservationIgnored var runScreenshotDisplayIndexBox: LockedBox<Int>
    @ObservationIgnored var previousRouteBeforeSettings: MainShellRoute?
    @ObservationIgnored var captureHiddenWindows: [CaptureHiddenWindow] = []
    @ObservationIgnored var capturePreviouslyKeyWindow: NSWindow?
    @ObservationIgnored var captureOutputURL: URL?
    @ObservationIgnored var captureOutputMode: FinishedRecordingReview.Mode?
    @ObservationIgnored var lastPresentedFinishedRecordingReview: FinishedRecordingReview?
    @ObservationIgnored var finishedRecordingDidCreateTask: Bool = false
    @ObservationIgnored var activeRunID: UUID?
    @ObservationIgnored var pinnedTaskIDs: Set<String> = []

    var tasks: [TaskRecord]
    var selectedTaskID: String?
    var route: MainShellRoute
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
    var selectedRunDisplayID: Int?
    var isCapturing: Bool
    var captureStartedAt: Date?
    var isExtractingTask: Bool
    var extractingRecordingID: String?
    var isRunningTask: Bool
    var saveStatusMessage: String?
    var recordingStatusMessage: String?
    var extractionStatusMessage: String?
    var runStatusMessage: String?
    var clarificationStatusMessage: String?
    var apiKeyStatusMessage: String?
    var apiKeyErrorMessage: String?
    var errorMessage: String?
    var llmUserFacingIssue: LLMUserFacingIssue?
    var missingProviderKeyDialog: MissingProviderKeyDialog?
    var recordingPreflightDialogState: RecordingPreflightDialogState?
    var runTaskPreflightDialogState: RunTaskPreflightDialogState?
    var finishedRecordingReview: FinishedRecordingReview?
    var llmCallLog: [LLMCallLogEntry]
    var executionTrace: [ExecutionTraceEntry]
    var runHistory: [AgentRunRecord]
    var runScreenshotLogByRunID: [UUID: [LLMScreenshotLogEntry]]
    var isCapturingDiagnosticScreenshot: Bool
    var diagnosticScreenshotStatusMessage: String?
    var diagnosticTraceStatusMessage: String?
    var lastDiagnosticScreenshotPNGData: Data?
    var lastDiagnosticScreenshotWidth: Int?
    var lastDiagnosticScreenshotHeight: Int?

    var isShowingDeleteTaskAlert: Bool
    var pendingDeleteTaskID: String?

    init(
        taskService: TaskService = TaskService(),
        taskExtractionService: TaskExtractionService? = nil,
        heartbeatQuestionService: HeartbeatQuestionService = HeartbeatQuestionService(),
        automationEngine: (any AutomationEngine)? = nil,
        apiKeyStore: any APIKeyStore = KeychainAPIKeyStore(),
        userDefaults: UserDefaults = .standard,
        permissionService: any PermissionService = MacPermissionService(),
        captureService: any RecordingCaptureService = ShellRecordingCaptureService(),
        overlayService: any RecordingOverlayService = ScreenRecordingOverlayService(),
        recordingControlOverlayService: any RecordingControlOverlayService = HUDWindowRecordingControlOverlayService(),
        agentControlOverlayService: any AgentControlOverlayService = HUDWindowAgentControlOverlayService(),
        userInterruptionMonitor: any UserInterruptionMonitor = QuartzUserInterruptionMonitor(),
        agentCursorPresentationService: any AgentCursorPresentationService = AccessibilityAgentCursorPresentationService(),
        prepareDesktopForRun: @escaping @MainActor () -> Int = MainShellStateStore.prepareDesktopByHidingRunningApps,
        revealAppAfterRunCancellation: @escaping @MainActor () -> Void = MainShellStateStore.revealAppWindowsAfterRunCancellation
    ) {
        self.userDefaults = userDefaults
        let callRecorder = LLMCallRecorder(maxEntries: 200)
        let screenshotRecorder = LLMScreenshotRecorder(maxEntries: 120)
        let traceRecorder = ExecutionTraceRecorder(maxEntries: 400)
        let runDisplayIndexBox = LockedBox<Int>(1)
        self.taskService = taskService
        self.apiKeyStore = apiKeyStore
        self.permissionService = permissionService
        self.taskExtractionService = taskExtractionService ?? TaskExtractionService(
            llmClient: GeminiVideoLLMClient(apiKeyStore: apiKeyStore)
        )
        self.heartbeatQuestionService = heartbeatQuestionService
        self.runScreenshotDisplayIndexBox = runDisplayIndexBox
        let openAIRunner = OpenAIComputerUseRunner(
            apiKeyStore: apiKeyStore,
            callLogSink: { entry in
                callRecorder.record(entry)
            },
            screenshotLogSink: { entry in
                screenshotRecorder.record(entry)
            },
            traceSink: { entry in
                traceRecorder.record(entry)
            },
            screenshotProvider: {
                let displayIndex = runDisplayIndexBox.value
                let excludedWindowNumbers = [
                    agentControlOverlayService.windowNumberForScreenshotExclusion(),
                    overlayService.windowNumberForScreenshotExclusion()
                ].compactMap { $0 }
                return try OpenAIComputerUseRunner.captureDisplayScreenshot(displayIndex: displayIndex, excludingWindowNumbers: excludedWindowNumbers)
            }
        )

        self.automationEngine = automationEngine ?? OpenAIAutomationEngine(runner: openAIRunner)
        self.captureService = captureService
        self.overlayService = overlayService
        self.recordingControlOverlayService = recordingControlOverlayService
        self.agentControlOverlayService = agentControlOverlayService
        self.userInterruptionMonitor = userInterruptionMonitor
        self.agentCursorPresentationService = agentCursorPresentationService
        self.prepareDesktopForRun = prepareDesktopForRun
        self.revealAppAfterRunCancellation = revealAppAfterRunCancellation
        self.llmCallRecorder = callRecorder
        self.llmScreenshotRecorder = screenshotRecorder
        self.executionTraceRecorder = traceRecorder
        self.runTaskHandle = nil
        self.tasks = []
        self.selectedTaskID = nil
        self.route = .newTask
        self.providerSetupState = ProviderSetupState(
            hasOpenAIKey: apiKeyStore.hasKey(for: .openAI),
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
        self.selectedRunDisplayID = nil
        self.isCapturing = false
        self.captureStartedAt = nil
        self.isExtractingTask = false
        self.extractingRecordingID = nil
        self.isRunningTask = false
        self.saveStatusMessage = nil
        self.recordingStatusMessage = nil
        self.extractionStatusMessage = nil
        self.runStatusMessage = nil
        self.clarificationStatusMessage = nil
        self.apiKeyStatusMessage = nil
        self.apiKeyErrorMessage = nil
        self.errorMessage = nil
        self.llmUserFacingIssue = nil
        self.missingProviderKeyDialog = nil
        self.recordingPreflightDialogState = nil
        self.runTaskPreflightDialogState = nil
        self.finishedRecordingReview = nil
        self.llmCallLog = []
        self.executionTrace = []
        self.runHistory = []
        self.runScreenshotLogByRunID = [:]
        self.isCapturingDiagnosticScreenshot = false
        self.diagnosticScreenshotStatusMessage = nil
        self.diagnosticTraceStatusMessage = nil
        self.lastDiagnosticScreenshotPNGData = nil
        self.lastDiagnosticScreenshotWidth = nil
        self.lastDiagnosticScreenshotHeight = nil
        self.isShowingDeleteTaskAlert = false
        self.pendingDeleteTaskID = nil

        self.pinnedTaskIDs = Self.loadPinnedTaskIDs(from: userDefaults)

        callRecorder.onRecord = { [weak self] entry in
            DispatchQueue.main.async {
                self?.llmCallLog = callRecorder.snapshot()
                self?.appendLLMCallEventToActiveRun(entry)
            }
        }

        traceRecorder.onRecord = { [weak self] entry in
            DispatchQueue.main.async {
                self?.executionTrace = traceRecorder.snapshot()
                self?.appendTraceEventToActiveRun(entry)
            }
        }

        screenshotRecorder.onRecord = { [weak self] entry in
            DispatchQueue.main.async {
                self?.appendScreenshotLogToActiveRun(entry)
            }
        }
    }

    deinit {
        overlayService.hideBorder()
        _ = agentCursorPresentationService.deactivateTakeoverCursor()
    }

    var selectedTask: TaskRecord? {
        guard let selectedTaskID else {
            return nil
        }
        return tasks.first(where: { $0.id == selectedTaskID })
    }

    var activeLLMUserFacingIssue: LLMUserFacingIssue? {
        guard let llmUserFacingIssue else {
            return nil
        }
        guard errorMessage == llmUserFacingIssue.userMessage else {
            return nil
        }
        return llmUserFacingIssue
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

}

final class LLMCallRecorder {
    private let lock = NSLock()
    private var entries: [LLMCallLogEntry] = []
    private let maxEntries: Int

    var onRecord: ((LLMCallLogEntry) -> Void)?

    init(maxEntries: Int) {
        self.maxEntries = max(1, maxEntries)
    }

    func record(_ entry: LLMCallLogEntry) {
        lock.lock()
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        lock.unlock()

        onRecord?(entry)
    }

    func snapshot() -> [LLMCallLogEntry] {
        lock.lock()
        let copy = entries
        lock.unlock()
        return copy
    }

    func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
}

final class LLMScreenshotRecorder {
    private let lock = NSLock()
    private var entries: [LLMScreenshotLogEntry] = []
    private let maxEntries: Int

    var onRecord: ((LLMScreenshotLogEntry) -> Void)?

    init(maxEntries: Int) {
        self.maxEntries = max(1, maxEntries)
    }

    func record(_ entry: LLMScreenshotLogEntry) {
        lock.lock()
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        lock.unlock()

        onRecord?(entry)
    }

    func snapshot() -> [LLMScreenshotLogEntry] {
        lock.lock()
        let copy = entries
        lock.unlock()
        return copy
    }

    func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
}

final class ExecutionTraceRecorder {
    private let lock = NSLock()
    private var entries: [ExecutionTraceEntry] = []
    private let maxEntries: Int

    var onRecord: ((ExecutionTraceEntry) -> Void)?

    init(maxEntries: Int) {
        self.maxEntries = max(1, maxEntries)
    }

    func record(_ entry: ExecutionTraceEntry) {
        lock.lock()
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        lock.unlock()

        onRecord?(entry)
    }

    func snapshot() -> [ExecutionTraceEntry] {
        lock.lock()
        let copy = entries
        lock.unlock()
        return copy
    }

    func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
}
