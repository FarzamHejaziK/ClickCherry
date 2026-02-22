import Foundation
import Observation
import AppKit
import CoreGraphics

enum MainShellRoute: Equatable {
    case newTask
    case task(String)
    case settings
}

struct MissingProviderKeyDialog: Equatable {
    enum Action: Equatable {
        case extractTask
        case runTask
    }

    let provider: ProviderIdentifier
    let action: Action

    var title: String {
        switch provider {
        case .gemini:
            return "Gemini API key required"
        case .openAI:
            return "OpenAI API key required"
        }
    }

    var message: String {
        switch action {
        case .extractTask:
            return "Enter your \(providerDisplayName) API key before extracting. Open Settings to add it."
        case .runTask:
            return "Enter your \(providerDisplayName) API key before running the task. Open Settings to add it."
        }
    }

    private var providerDisplayName: String {
        switch provider {
        case .openAI:
            return "OpenAI"
        case .gemini:
            return "Gemini"
        }
    }
}

enum RecordingPreflightRequirement: String, Identifiable, Equatable {
    case geminiAPIKey
    case screenRecording
    case microphone
    case inputMonitoring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .geminiAPIKey:
            return "Gemini API key"
        case .screenRecording:
            return "Screen Recording"
        case .microphone:
            return "Microphone (Voice)"
        case .inputMonitoring:
            return "Input Monitoring"
        }
    }

    var detail: String {
        switch self {
        case .geminiAPIKey:
            return "Required to extract tasks after recording."
        case .screenRecording:
            return "Required to capture your screen."
        case .microphone:
            return "Required to record voice audio."
        case .inputMonitoring:
            return "Required so Escape can stop recording."
        }
    }

    var permission: AppPermission? {
        switch self {
        case .screenRecording:
            return .screenRecording
        case .microphone:
            return .microphone
        case .inputMonitoring:
            return .inputMonitoring
        case .geminiAPIKey:
            return nil
        }
    }
}

struct RecordingPreflightDialogState: Equatable {
    var missingRequirements: [RecordingPreflightRequirement]

    var title: String {
        "Recording Setup Required"
    }

    var message: String {
        "Complete the missing items below before starting a recording."
    }
}

enum RunTaskPreflightRequirement: String, Identifiable, Equatable {
    case openAIAPIKey
    case accessibility

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAIAPIKey:
            return "OpenAI API key"
        case .accessibility:
            return "Accessibility"
        }
    }

    var detail: String {
        switch self {
        case .openAIAPIKey:
            return "Required to run tasks with the agent."
        case .accessibility:
            return "Required so the agent can click and type."
        }
    }

    var permission: AppPermission? {
        switch self {
        case .accessibility:
            return .accessibility
        case .openAIAPIKey:
            return nil
        }
    }
}

struct RunTaskPreflightDialogState: Equatable {
    var missingRequirements: [RunTaskPreflightRequirement]

    var title: String {
        "Run Task Setup Required"
    }

    var message: String {
        "Complete the missing items below before running this task."
    }
}

@Observable
final class MainShellStateStore {
    private enum CaptureWindowHideMode {
        case miniaturized
        case orderedOut
    }

    private struct CaptureHiddenWindow {
        let window: NSWindow
        let mode: CaptureWindowHideMode
    }

    private final class LockedBox<Value>: @unchecked Sendable {
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

    private let taskService: TaskService
    private let taskExtractionService: TaskExtractionService
    private let heartbeatQuestionService: HeartbeatQuestionService
    private let automationEngine: any AutomationEngine
    private let apiKeyStore: any APIKeyStore
    private let permissionService: any PermissionService
    private let captureService: any RecordingCaptureService
    private let overlayService: any RecordingOverlayService
    private let recordingControlOverlayService: any RecordingControlOverlayService
    private let agentControlOverlayService: any AgentControlOverlayService
    private let userInterruptionMonitor: any UserInterruptionMonitor
    private let agentCursorPresentationService: any AgentCursorPresentationService
    private let prepareDesktopForRun: @MainActor () -> Int
    private let llmCallRecorder: LLMCallRecorder
    private let llmScreenshotRecorder: LLMScreenshotRecorder
    private let executionTraceRecorder: ExecutionTraceRecorder
    private let userDefaults: UserDefaults
    private var runTaskHandle: Task<Void, Never>?
    @ObservationIgnored private var runScreenshotDisplayIndexBox: LockedBox<Int>
    @ObservationIgnored private var previousRouteBeforeSettings: MainShellRoute?
    @ObservationIgnored private var captureHiddenWindows: [CaptureHiddenWindow] = []
    @ObservationIgnored private var capturePreviouslyKeyWindow: NSWindow?
    @ObservationIgnored private var captureOutputURL: URL?
    @ObservationIgnored private var captureOutputMode: FinishedRecordingReview.Mode?
    @ObservationIgnored private var lastPresentedFinishedRecordingReview: FinishedRecordingReview?
    @ObservationIgnored private var finishedRecordingDidCreateTask: Bool = false
    @ObservationIgnored private var activeRunID: UUID?
    @ObservationIgnored private var pinnedTaskIDs: Set<String> = []

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
        prepareDesktopForRun: @escaping @MainActor () -> Int = MainShellStateStore.prepareDesktopByHidingRunningApps
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

    func reloadTasks() {
        do {
            let loaded = try taskService.listTasks()
            tasks = sortTasksPinnedFirst(loaded)
            if let selectedTaskID, tasks.contains(where: { $0.id == selectedTaskID }) == false {
                self.selectedTaskID = nil
                if case .task = route {
                    route = .newTask
                }
            }
            loadSelectedTaskHeartbeat()
            loadSelectedTaskRecordings()
            loadSelectedTaskRunHistory()
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
            openTask(created.id)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to create task."
        }
    }

    func openNewTask() {
        route = .newTask
        guard !isCapturing else {
            return
        }
        selectedTaskID = nil
        heartbeatMarkdown = ""
        clarificationQuestions = []
        selectedClarificationQuestionID = nil
        clarificationAnswerDraft = ""
        recordings = []
        runHistory = []
        runScreenshotLogByRunID = [:]
        saveStatusMessage = nil
        recordingStatusMessage = nil
        extractionStatusMessage = nil
        runStatusMessage = nil
        clarificationStatusMessage = nil
        errorMessage = nil
        llmUserFacingIssue = nil
    }

    func openSettings() {
        if route != .settings {
            previousRouteBeforeSettings = route
        }
        route = .settings
    }

    func closeSettings() {
        if let previousRouteBeforeSettings {
            route = previousRouteBeforeSettings
        } else {
            route = .newTask
        }
    }

    func permissionStatus(for permission: AppPermission) -> PermissionGrantStatus {
        permissionService.currentStatus(for: permission)
    }

    func openPermissionSettings(for permission: AppPermission) {
        permissionService.requestAccessAndOpenSystemSettings(for: permission)
    }

    func resetOnboardingAndReturnToSetup() {
        userDefaults.set(false, forKey: "onboarding.completed")
        userDefaults.synchronize()
        NotificationCenter.default.post(name: .clickCherryResetOnboardingRequested, object: nil)
    }

    func resetSetupAndReturnToOnboarding() {
        do {
            try apiKeyStore.setKey(nil, for: .openAI)
            try apiKeyStore.setKey(nil, for: .gemini)
            updateProviderSetupState(saved: false, for: .openAI)
            updateProviderSetupState(saved: false, for: .gemini)
            apiKeyStatusMessage = "Cleared OpenAI/Gemini API keys and returned to onboarding."
            apiKeyErrorMessage = "OpenAI API key is not saved."
        } catch {
            apiKeyStatusMessage = nil
            apiKeyErrorMessage = "Failed to clear one or more API keys. Onboarding reset still applied."
        }

        let permissionResetOutcome = Self.resetSystemPermissionsViaTCC()
        switch permissionResetOutcome {
        case .success:
            errorMessage = "Reset macOS permissions and onboarding for this app. The app will relaunch so macOS permission state fully refreshes."
        case .notAvailable:
            errorMessage = "Could not reset macOS permissions automatically. Use System Settings > Privacy & Security to revoke them manually."
        case .failed:
            errorMessage = "Automatic permission reset failed. Use System Settings > Privacy & Security to revoke permissions manually."
        }
        resetOnboardingAndReturnToSetup()

        if permissionResetOutcome == .success {
            Self.relaunchApplicationAfterReset()
        }
    }

    func openTask(_ taskID: String) {
        route = .task(taskID)
        selectedTaskID = taskID
        clarificationAnswerDraft = ""
        clarificationStatusMessage = nil
        runStatusMessage = nil
        loadSelectedTaskHeartbeat()
        loadSelectedTaskRecordings()
        loadSelectedTaskRunHistory()
    }

    func toggleNewTaskRecording() {
        if isCapturing {
            stopCapture()
            return
        }

        // Do not create a task until the user explicitly chooses `Extract task` after recording finishes.
        // Recording is staged to a temporary file first.
        selectedTaskID = nil
        route = .newTask
        startCapture()
    }

    func refreshProviderKeysState() {
        providerSetupState = ProviderSetupState(
            hasOpenAIKey: apiKeyStore.hasKey(for: .openAI),
            hasGeminiKey: apiKeyStore.hasKey(for: .gemini)
        )
        if providerSetupState.hasOpenAIKey {
            if apiKeyErrorMessage == "OpenAI API key is not saved." {
                apiKeyErrorMessage = nil
            }
        } else {
            apiKeyErrorMessage = "OpenAI API key is not saved."
        }
    }

    func isTaskPinned(_ taskID: String) -> Bool {
        pinnedTaskIDs.contains(taskID)
    }

    func togglePinned(taskID: String) {
        if pinnedTaskIDs.contains(taskID) {
            pinnedTaskIDs.remove(taskID)
        } else {
            pinnedTaskIDs.insert(taskID)
        }
        persistPinnedTaskIDs()
        tasks = sortTasksPinnedFirst(tasks)
    }

    func requestDeleteTask(taskID: String) {
        pendingDeleteTaskID = taskID
        isShowingDeleteTaskAlert = true
    }

    func cancelDeleteTask() {
        isShowingDeleteTaskAlert = false
        pendingDeleteTaskID = nil
    }

    func confirmDeleteTask() {
        guard let taskID = pendingDeleteTaskID else {
            cancelDeleteTask()
            return
        }

        // Capture selection before `reloadTasks()` potentially clears it.
        let wasOpenTask =
            selectedTaskID == taskID ||
            route == .task(taskID)

        do {
            try taskService.deleteTask(taskId: taskID)
            pinnedTaskIDs.remove(taskID)
            persistPinnedTaskIDs()
            cancelDeleteTask()
            reloadTasks()
            if wasOpenTask {
                openNewTask()
            }
            errorMessage = nil
        } catch {
            // Keep the alert dismissed but surface a message.
            cancelDeleteTask()
            errorMessage = "Failed to delete task."
        }
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
            if provider == .openAI {
                apiKeyErrorMessage = nil
            }
            return true
        } catch {
            apiKeyStatusMessage = nil
            apiKeyErrorMessage = "Failed to save \(providerDisplayName(provider)) API key."
            return false
        }
    }

    private static let pinnedTasksUserDefaultsKey = "tasks.pinned.ids"

    private static func loadPinnedTaskIDs(from defaults: UserDefaults) -> Set<String> {
        let raw = defaults.array(forKey: pinnedTasksUserDefaultsKey) as? [String] ?? []
        return Set(raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }

    private enum PermissionResetOutcome {
        case success
        case notAvailable
        case failed
    }

    private static func resetSystemPermissionsViaTCC() -> PermissionResetOutcome {
        // Prevent test execution from mutating host TCC state.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return .notAvailable
        }

        guard let bundleIdentifier = Bundle.main.bundleIdentifier, !bundleIdentifier.isEmpty else {
            return .notAvailable
        }

        let executable = "/usr/bin/tccutil"
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return .notAvailable
        }

        if runTCCReset(executablePath: executable, service: "All", bundleIdentifier: bundleIdentifier) {
            return .success
        }

        let services = ["Accessibility", "Microphone", "ScreenCapture", "ListenEvent", "AppleEvents", "PostEvent"]
        var didResetAtLeastOne = false
        for service in services {
            if runTCCReset(executablePath: executable, service: service, bundleIdentifier: bundleIdentifier) {
                didResetAtLeastOne = true
            }
        }
        return didResetAtLeastOne ? .success : .failed
    }

    private static func runTCCReset(executablePath: String, service: String, bundleIdentifier: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["reset", service, bundleIdentifier]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func relaunchApplicationAfterReset() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        let appBundlePath = Bundle.main.bundlePath
        guard !appBundlePath.isEmpty else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            relaunch.arguments = ["-n", appBundlePath]
            try? relaunch.run()
            NSApp.terminate(nil)
        }
    }

    private func persistPinnedTaskIDs() {
        let ordered = pinnedTaskIDs.sorted()
        userDefaults.set(ordered, forKey: Self.pinnedTasksUserDefaultsKey)
    }

    private func sortTasksPinnedFirst(_ input: [TaskRecord]) -> [TaskRecord] {
        // Stable, predictable ordering:
        // 1) pinned tasks first (most-recent createdAt first within pinned)
        // 2) then unpinned tasks (most-recent createdAt first)
        let pinned = input.filter { pinnedTaskIDs.contains($0.id) }.sorted(by: { $0.createdAt > $1.createdAt })
        let unpinned = input.filter { !pinnedTaskIDs.contains($0.id) }.sorted(by: { $0.createdAt > $1.createdAt })
        return pinned + unpinned
    }

    func clearProviderKey(for provider: ProviderIdentifier) {
        do {
            try apiKeyStore.setKey(nil, for: provider)
            updateProviderSetupState(saved: false, for: provider)
            apiKeyStatusMessage = "Removed \(providerDisplayName(provider)) API key."
            apiKeyErrorMessage = provider == .openAI ? "OpenAI API key is not saved." : nil
        } catch {
            apiKeyStatusMessage = nil
            apiKeyErrorMessage = "Failed to remove \(providerDisplayName(provider)) API key."
        }
    }

    func clearLLMCallLog() {
        llmCallRecorder.clear()
        llmCallLog = []
    }

    func clearExecutionTrace() {
        executionTraceRecorder.clear()
        executionTrace = []
    }

    @MainActor
    func copyExecutionTraceToPasteboard(onlyToolUse: Bool) {
        let entries = onlyToolUse ? executionTrace.filter { $0.kind == .toolUse } : executionTrace
        guard !entries.isEmpty else {
            diagnosticTraceStatusMessage = "No trace entries to copy."
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let lines = entries.map { entry in
            "\(formatter.string(from: entry.timestamp)) \(entry.kind.rawValue.uppercased()): \(entry.message)"
        }
        let output = lines.joined(separator: "\n")

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(output, forType: .string)
        diagnosticTraceStatusMessage = "Copied \(entries.count) trace line(s) to clipboard."
    }

    @MainActor
    func copyLLMCallLogToPasteboard(onlyFailures: Bool) {
        let entries = onlyFailures ? llmCallLog.filter { $0.outcome == .failure } : llmCallLog
        guard !entries.isEmpty else {
            diagnosticTraceStatusMessage = "No LLM call entries to copy."
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var lines: [String] = []
        for entry in entries {
            var header = "\(formatter.string(from: entry.finishedAt)) \(entry.outcome == .success ? "OK" : "FAIL") \(entry.provider.rawValue)/\(entry.operation.rawValue) #\(entry.attempt)"
            if let status = entry.httpStatus {
                header += " HTTP \(status)"
            }
            header += " \(entry.durationMs)ms"

            lines.append(header)
            lines.append("  url: \(entry.url)")
            if let requestId = entry.requestId, !requestId.isEmpty {
                lines.append("  request-id: \(requestId)")
            }
            if let bytesSent = entry.bytesSent {
                lines.append("  bytes-sent: \(bytesSent)")
            }
            if let bytesReceived = entry.bytesReceived {
                lines.append("  bytes-received: \(bytesReceived)")
            }
            if let message = entry.message, !message.isEmpty {
                lines.append("  message: \(message)")
            }
            lines.append("")
        }

        let output = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(output, forType: .string)
        diagnosticTraceStatusMessage = "Copied \(entries.count) LLM call(s) to clipboard."
    }

    @MainActor
    func copyAllDiagnosticsToPasteboard(onlyToolUseTrace: Bool, onlyLLMFailures: Bool) {
        let traceEntries = onlyToolUseTrace ? executionTrace.filter { $0.kind == .toolUse } : executionTrace
        let llmEntries = onlyLLMFailures ? llmCallLog.filter { $0.outcome == .failure } : llmCallLog

        guard !traceEntries.isEmpty || !llmEntries.isEmpty else {
            diagnosticTraceStatusMessage = "No diagnostics to copy."
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var lines: [String] = []

        if !traceEntries.isEmpty {
            lines.append("=== EXECUTION TRACE ===")
            lines.append(contentsOf: traceEntries.map { entry in
                "\(formatter.string(from: entry.timestamp)) \(entry.kind.rawValue.uppercased()): \(entry.message)"
            })
            lines.append("")
        }

        if !llmEntries.isEmpty {
            lines.append("=== LLM CALLS ===")
            for entry in llmEntries {
                var header = "\(formatter.string(from: entry.finishedAt)) \(entry.outcome == .success ? "OK" : "FAIL") \(entry.provider.rawValue)/\(entry.operation.rawValue) #\(entry.attempt)"
                if let status = entry.httpStatus {
                    header += " HTTP \(status)"
                }
                header += " \(entry.durationMs)ms"
                lines.append(header)
                lines.append("  url: \(entry.url)")
                if let requestId = entry.requestId, !requestId.isEmpty {
                    lines.append("  request-id: \(requestId)")
                }
                if let message = entry.message, !message.isEmpty {
                    lines.append("  message: \(message)")
                }
                lines.append("")
            }
        }

        let output = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(output, forType: .string)
        diagnosticTraceStatusMessage = "Copied diagnostics to clipboard."
    }

    @MainActor
    func captureDiagnosticScreenshot() async {
        guard !isCapturingDiagnosticScreenshot else {
            return
        }

        isCapturingDiagnosticScreenshot = true
        diagnosticScreenshotStatusMessage = "Capturing screenshot..."

        do {
            let capture = try await Task.detached {
                try DesktopScreenshotService.captureMainDisplayPNG()
            }.value

            lastDiagnosticScreenshotPNGData = capture.pngData
            lastDiagnosticScreenshotWidth = capture.width
            lastDiagnosticScreenshotHeight = capture.height
            diagnosticScreenshotStatusMessage = "Captured \(capture.width)x\(capture.height) (\(capture.pngData.count) bytes)."
        } catch DesktopScreenshotServiceError.captureFailed {
            diagnosticScreenshotStatusMessage = "Screenshot capture failed. Ensure Screen Recording permission is granted."
        } catch DesktopScreenshotServiceError.decodeFailed {
            diagnosticScreenshotStatusMessage = "Screenshot captured but failed to decode image."
        } catch {
            diagnosticScreenshotStatusMessage = "Screenshot capture failed: \(error.localizedDescription)"
        }

        isCapturingDiagnosticScreenshot = false
    }

    func selectTask(_ taskID: String?) {
        guard let taskID else {
            openNewTask()
            return
        }

        openTask(taskID)
    }

    func dismissMissingProviderKeyDialog() {
        missingProviderKeyDialog = nil
    }

    func dismissRecordingPreflightDialog() {
        recordingPreflightDialogState = nil
    }

    func dismissRunTaskPreflightDialog() {
        runTaskPreflightDialogState = nil
    }

    func openSettingsForMissingProviderKeyDialog() {
        openSettings()
        dismissMissingProviderKeyDialog()
    }

    func openSettingsForActiveLLMUserFacingIssue() {
        openSettings()
    }

    func openProviderConsoleForActiveLLMUserFacingIssue() {
        guard let issue = activeLLMUserFacingIssue,
              let url = issue.providerConsoleURL else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func openSettingsForRecordingPreflightRequirement(_ requirement: RecordingPreflightRequirement) {
        guard let permission = requirement.permission else {
            openSettings()
            return
        }
        openPermissionSettings(for: permission)
    }

    func openSettingsForRunTaskPreflightRequirement(_ requirement: RunTaskPreflightRequirement) {
        guard let permission = requirement.permission else {
            openSettings()
            return
        }
        openPermissionSettings(for: permission)
    }

    @discardableResult
    func saveGeminiKeyFromRecordingPreflight(_ rawKey: String) -> Bool {
        let didSave = saveProviderKey(rawKey, for: .gemini)
        refreshRecordingPreflightDialogState()
        return didSave
    }

    func continueAfterRecordingPreflightDialog() {
        refreshRecordingPreflightDialogState()
        guard recordingPreflightDialogState == nil else {
            return
        }
        startCapture()
    }

    @discardableResult
    func saveOpenAIKeyFromRunTaskPreflight(_ rawKey: String) -> Bool {
        let didSave = saveProviderKey(rawKey, for: .openAI)
        refreshRunTaskPreflightDialogState()
        return didSave
    }

    @MainActor
    func continueAfterRunTaskPreflightDialog() {
        refreshRunTaskPreflightDialogState()
        guard runTaskPreflightDialogState == nil else {
            return
        }
        startRunTaskNow()
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

    func loadSelectedTaskRunHistory() {
        guard let selectedTaskID else {
            runHistory = []
            runScreenshotLogByRunID = [:]
            return
        }

        do {
            runHistory = try taskService.listAgentRunLogs(taskId: selectedTaskID)
            runScreenshotLogByRunID = [:]
        } catch {
            runHistory = []
            runScreenshotLogByRunID = [:]
            // Don't hard-fail the whole page if history is malformed.
        }
    }

    func refreshCaptureDisplays() {
        let displays = captureService.listDisplays()
        availableCaptureDisplays = displays
        if let selectedCaptureDisplayID,
           displays.contains(where: { $0.id == selectedCaptureDisplayID }) {
            // Keep selection.
        } else {
            selectedCaptureDisplayID = displays.first?.id
        }

        if let selectedRunDisplayID,
           displays.contains(where: { $0.id == selectedRunDisplayID }) {
            // Keep selection.
        } else {
            selectedRunDisplayID = displays.first?.id
        }
    }

    private func resolvedDisplayOption(selectedID: Int?) -> CaptureDisplayOption? {
        if let selectedID,
           let selectedDisplay = availableCaptureDisplays.first(where: { $0.id == selectedID }) {
            return selectedDisplay
        }
        return availableCaptureDisplays.first
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

    var availableMicrophoneDeviceCount: Int {
        availableCaptureAudioInputs.reduce(0) { count, option in
            switch option.mode {
            case .device:
                return count + 1
            default:
                return count
            }
        }
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
        guard requireProviderKey(for: .gemini, action: .extractTask) else {
            extractionStatusMessage = nil
            return
        }
        guard !isExtractingTask else {
            return
        }

        isExtractingTask = true
        extractingRecordingID = recording.id
        extractionStatusMessage = "Extracting task from \(recording.fileName)..."
        errorMessage = nil
        llmUserFacingIssue = nil

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
            llmUserFacingIssue = nil
        } catch TaskExtractionServiceError.invalidModelOutput {
            extractionStatusMessage = nil
            errorMessage = "Extraction output was invalid. HEARTBEAT.md was not changed."
            llmUserFacingIssue = nil
        } catch let error as GeminiLLMClientError {
            extractionStatusMessage = nil
            if case .userFacingIssue(let issue) = error {
                llmUserFacingIssue = issue
                errorMessage = issue.userMessage
            } else {
                llmUserFacingIssue = nil
                errorMessage = error.errorDescription ?? "Gemini request failed."
            }
        } catch LLMClientError.notConfigured {
            extractionStatusMessage = nil
            errorMessage = "Task extraction LLM client is not configured yet."
            llmUserFacingIssue = nil
        } catch {
            extractionStatusMessage = nil
            errorMessage = "Failed to extract task from recording."
            llmUserFacingIssue = nil
        }

        isExtractingTask = false
        extractingRecordingID = nil
    }

    @MainActor
    func startRunTaskNow() {
        guard let selectedTaskID else {
            return
        }
        guard !isRunningTask else {
            return
        }

        guard ensureRunTaskPreflightRequirements() else {
            return
        }

        // Ensure the runner uses the selected display for screenshots/tool coordinates.
        refreshCaptureDisplays()
        guard let runDisplay = resolvedDisplayOption(selectedID: selectedRunDisplayID) else {
            errorMessage = "No display detected for run."
            return
        }
        selectedRunDisplayID = runDisplay.id
        let runDisplayIndex = runDisplay.screencaptureDisplayIndex
        runScreenshotDisplayIndexBox.value = runDisplayIndex

        // Show a red border on the selected display while the agent is running.
        // The overlay window is excluded from the agent's screenshots via ScreenCaptureKit window exclusion.
        overlayService.showBorder(displayID: runDisplayIndex)

        beginRun(displayIndex: runDisplayIndex)
        executionTraceRecorder.record(
            ExecutionTraceEntry(kind: .info, message: "Run display set to Display \(runDisplayIndex).")
        )

        let hiddenAppsCount = prepareDesktopForRun()
        executionTraceRecorder.record(
            ExecutionTraceEntry(kind: .info, message: "Prepared screen by hiding \(hiddenAppsCount) running app(s).")
        )

        isRunningTask = true
        runStatusMessage = "Running task..."
        errorMessage = nil
        llmUserFacingIssue = nil
        let startedAt = Date()

        executionTraceRecorder.record(ExecutionTraceEntry(kind: .info, message: "Run requested for task \(selectedTaskID)."))
        agentControlOverlayService.showAgentInControl(displayID: runDisplayIndex)
        if agentCursorPresentationService.activateTakeoverCursor() {
            executionTraceRecorder.record(ExecutionTraceEntry(kind: .info, message: "Cursor presentation left unchanged during agent takeover."))
        } else {
            executionTraceRecorder.record(ExecutionTraceEntry(kind: .error, message: "Failed to activate takeover cursor presentation."))
        }

        let didStartMonitor = userInterruptionMonitor.start { [weak self] in
            self?.handleUserInterruptionDuringRun()
        }
        if !didStartMonitor {
            executionTraceRecorder.record(
                ExecutionTraceEntry(
                    kind: .info,
                    message: "Escape-key monitoring unavailable (Input Monitoring not granted). Run continues without Escape-to-stop."
                )
            )
        }

        // Run off the main actor to avoid blocking UI; cancellation is supported via `runTaskHandle.cancel()`.
        let taskMarkdown = heartbeatMarkdown
        runTaskHandle?.cancel()
        runTaskHandle = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let result = await self.automationEngine.run(taskMarkdown: taskMarkdown)
            await MainActor.run {
                self.finishRunTaskNow(taskId: selectedTaskID, startedAt: startedAt, result: result)
            }
        }
    }

    @MainActor
    func runTaskNow() async {
        guard let selectedTaskID else {
            return
        }
        guard !isRunningTask else {
            return
        }

        guard ensureRunTaskPreflightRequirements() else {
            return
        }

        refreshCaptureDisplays()
        guard let runDisplay = resolvedDisplayOption(selectedID: selectedRunDisplayID) else {
            errorMessage = "No display detected for run."
            return
        }
        selectedRunDisplayID = runDisplay.id
        let runDisplayIndex = runDisplay.screencaptureDisplayIndex
        runScreenshotDisplayIndexBox.value = runDisplayIndex

        await MainActor.run {
            beginRun(displayIndex: runDisplayIndex)
        }
        executionTraceRecorder.record(
            ExecutionTraceEntry(kind: .info, message: "Run display set to Display \(runDisplayIndex).")
        )

        let hiddenAppsCount = prepareDesktopForRun()
        executionTraceRecorder.record(
            ExecutionTraceEntry(kind: .info, message: "Prepared screen by hiding \(hiddenAppsCount) running app(s).")
        )

        isRunningTask = true
        runStatusMessage = "Running task..."
        errorMessage = nil
        llmUserFacingIssue = nil
        let startedAt = Date()

        executionTraceRecorder.record(ExecutionTraceEntry(kind: .info, message: "Run requested for task \(selectedTaskID)."))

        let result = await automationEngine.run(taskMarkdown: heartbeatMarkdown)
        finishRunTaskNow(taskId: selectedTaskID, startedAt: startedAt, result: result)
    }

    func stopRunTask() {
        guard isRunningTask else {
            return
        }
        agentControlOverlayService.hideAgentInControl()
        overlayService.hideBorder()
        userInterruptionMonitor.stop()
        if !agentCursorPresentationService.deactivateTakeoverCursor() {
            executionTraceRecorder.record(ExecutionTraceEntry(kind: .error, message: "Failed to deactivate takeover cursor presentation after cancellation request."))
        }
        runStatusMessage = "Cancelling..."
        executionTraceRecorder.record(ExecutionTraceEntry(kind: .cancelled, message: "Cancel requested by user."))
        runTaskHandle?.cancel()
    }

    private func finishRunTaskNow(taskId: String, startedAt: Date, result: AutomationRunResult) {
        defer {
            isRunningTask = false
            runTaskHandle = nil
        }

        agentControlOverlayService.hideAgentInControl()
        overlayService.hideBorder()
        userInterruptionMonitor.stop()
        if !agentCursorPresentationService.deactivateTakeoverCursor() {
            executionTraceRecorder.record(ExecutionTraceEntry(kind: .error, message: "Failed to deactivate takeover cursor presentation after run completion."))
        }

        var heartbeatChanged = false
        if result.outcome != .cancelled, !result.generatedQuestions.isEmpty {
            do {
                let updated = try heartbeatQuestionService.appendOpenQuestions(result.generatedQuestions, in: heartbeatMarkdown)
                try taskService.saveHeartbeat(taskId: taskId, markdown: updated)
                heartbeatMarkdown = updated
                saveStatusMessage = "Saved."
                heartbeatChanged = true
            } catch HeartbeatQuestionServiceError.noQuestionsToAppend {
                // Questions already exist in markdown.
            } catch {
                errorMessage = "Task run generated clarification questions but failed to update HEARTBEAT.md."
            }
        }

        let summary = AutomationRunSummary(
            startedAt: startedAt,
            finishedAt: Date(),
            outcome: result.outcome,
            executedSteps: result.executedSteps,
            generatedQuestions: result.generatedQuestions,
            errorMessage: result.errorMessage,
            llmSummary: result.llmSummary
        )
        do {
            _ = try taskService.saveRunSummary(taskId: taskId, summary: summary)
        } catch {
            errorMessage = "Task run finished but failed to persist run summary."
        }

        refreshClarificationQuestions()

        switch result.outcome {
        case .success:
            runStatusMessage = "Run complete."
        case .needsClarification:
            runStatusMessage = heartbeatChanged
                ? "Run needs clarification. HEARTBEAT.md was updated with follow-up questions."
                : "Run needs clarification."
        case .failed:
            runStatusMessage = "Run failed."
        case .cancelled:
            runStatusMessage = "Run cancelled."
        }

        if result.outcome == .cancelled {
            llmUserFacingIssue = nil
        } else if let issue = result.llmUserFacingIssue {
            llmUserFacingIssue = issue
            errorMessage = issue.userMessage
        } else if let resultError = result.errorMessage, !resultError.isEmpty {
            llmUserFacingIssue = nil
            errorMessage = resultError
        } else if result.outcome == .success {
            llmUserFacingIssue = nil
        }

        if let finished = finishActiveRun(outcome: result.outcome) {
            do {
                _ = try taskService.saveAgentRunLog(taskId: taskId, run: finished)
            } catch {
                // Keep the run visible in-memory even if persistence fails.
                if errorMessage == nil {
                    errorMessage = "Task run finished but failed to persist run log."
                }
            }
        }
    }

    private func handleUserInterruptionDuringRun() {
        guard isRunningTask else {
            return
        }

        agentControlOverlayService.hideAgentInControl()
        overlayService.hideBorder()
        userInterruptionMonitor.stop()
        if !agentCursorPresentationService.deactivateTakeoverCursor() {
            executionTraceRecorder.record(ExecutionTraceEntry(kind: .error, message: "Failed to deactivate takeover cursor presentation after Escape takeover."))
        }
        runStatusMessage = "Cancelling (Escape pressed)..."
        executionTraceRecorder.record(ExecutionTraceEntry(kind: .cancelled, message: "Escape pressed; cancelling run."))
        runTaskHandle?.cancel()
    }

    private func beginRun(displayIndex: Int) {
        let run = AgentRunRecord(startedAt: Date(), displayIndex: displayIndex)
        runHistory.insert(run, at: 0)
        runScreenshotLogByRunID[run.id] = []
        activeRunID = run.id
    }

    private func finishActiveRun(outcome: AutomationRunOutcome) -> AgentRunRecord? {
        guard let activeRunID else { return nil }
        guard let idx = runHistory.firstIndex(where: { $0.id == activeRunID }) else {
            self.activeRunID = nil
            return nil
        }
        runHistory[idx].finishedAt = Date()
        runHistory[idx].outcome = outcome
        let finished = runHistory[idx]
        self.activeRunID = nil
        return finished
    }

    private func shouldSuppressRunLogLine(_ message: String) -> Bool {
        let lower = message.lowercased()
        // The agent still captures screenshots for operation, but we do not retain or log them.
        if lower.contains("screenshot") { return true }
        if lower.contains("screen shot") { return true }
        if lower.contains("screencapture") { return true }
        if lower.contains("captured initial") && lower.contains("image") { return true }
        return false
    }

    private func appendTraceEventToActiveRun(_ entry: ExecutionTraceEntry) {
        guard let activeRunID else { return }
        guard !shouldSuppressRunLogLine(entry.message) else { return }

        let kind: AgentRunEvent.Kind
        switch entry.kind {
        case .info:
            kind = .info
        case .llmResponse:
            kind = .llm
        case .toolUse:
            kind = .tool
        case .localAction:
            kind = .action
        case .completion:
            kind = .completion
        case .cancelled:
            kind = .cancelled
        case .error:
            kind = .error
        }

        guard let idx = runHistory.firstIndex(where: { $0.id == activeRunID }) else { return }
        runHistory[idx].events.append(
            AgentRunEvent(timestamp: entry.timestamp, kind: kind, message: entry.message)
        )
    }

    private func appendLLMCallEventToActiveRun(_ entry: LLMCallLogEntry) {
        guard let activeRunID else { return }

        let ok = entry.outcome == .success
        let status = ok ? "OK" : "FAIL"
        var suffix: [String] = []
        if let httpStatus = entry.httpStatus {
            suffix.append("HTTP \(httpStatus)")
        }
        if entry.attempt > 1 {
            suffix.append("attempt \(entry.attempt)")
        }
        let extra = suffix.isEmpty ? "" : " (\(suffix.joined(separator: ", ")))"
        let message = "\(entry.provider.rawValue)/\(entry.operation.rawValue) \(status) \(entry.durationMs)ms\(extra)"

        guard let idx = runHistory.firstIndex(where: { $0.id == activeRunID }) else { return }
        runHistory[idx].events.append(
            AgentRunEvent(timestamp: entry.finishedAt, kind: .llm, message: message)
        )
    }

    private func appendScreenshotLogToActiveRun(_ entry: LLMScreenshotLogEntry) {
        guard let activeRunID else { return }
        var entries = runScreenshotLogByRunID[activeRunID] ?? []
        entries.append(entry)
        if entries.count > 40 {
            entries.removeFirst(entries.count - 40)
        }
        runScreenshotLogByRunID[activeRunID] = entries
    }

    @MainActor
    private static func prepareDesktopByHidingRunningApps() -> Int {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let finderBundleID = "com.apple.finder"
        var hiddenCount = 0

        for app in NSWorkspace.shared.runningApplications {
            guard app.processIdentifier != currentPID else { continue }
            guard app.activationPolicy == .regular else { continue }
            if app.bundleIdentifier == finderBundleID {
                continue
            }
            guard !app.isHidden else { continue }
            if app.hide() {
                hiddenCount += 1
            }
        }

        if let finder = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == finderBundleID }) {
            _ = finder.activate(options: [.activateIgnoringOtherApps])
        }

        return hiddenCount
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
        guard ensureRecordingPreflightRequirements() else {
            return
        }
        refreshCaptureDisplays()
        guard let captureDisplay = resolvedDisplayOption(selectedID: selectedCaptureDisplayID) else {
            errorMessage = "No display detected for capture."
            return
        }
        selectedCaptureDisplayID = captureDisplay.id
        let captureDisplayIndex = captureDisplay.screencaptureDisplayIndex
        guard !isRunningTask else {
            errorMessage = "Cannot start recording while a task is running."
            return
        }

        refreshCaptureAudioInputs()

        // Allow Escape to stop recording when the app is hidden/minimized.
        let didStartMonitor = userInterruptionMonitor.start { [weak self] in
            self?.handleUserInterruptionDuringCapture()
        }
        if didStartMonitor {
            recordingControlOverlayService.showRecordingHint(displayID: captureDisplayIndex)
        } else {
            recordingControlOverlayService.hideRecordingHint()
            // Keep the UI visible so the user can stop recording via the button.
            recordingStatusMessage =
                "Capture started, but Escape-to-stop is unavailable. Enable Input Monitoring in System Settings > Privacy & Security > Input Monitoring for TaskAgentMacOSApp."
        }

        // Show overlays immediately (border + HUD).
        overlayService.showBorder(displayID: captureDisplayIndex)

        // Hide our own UI windows early (especially for multi-display), but avoid hiding before the
        // Screen Recording permission prompt can be shown.
        if didStartMonitor && CGPreflightScreenCaptureAccess() {
            hideAppWindowsForCapture()
        }

        let requestedAudioInput = selectedAudioInputMode

        let outputURL: URL
        let outputMode: FinishedRecordingReview.Mode
        do {
            if route == .newTask {
                outputURL = try taskService.makeStagingCaptureOutputURL()
                outputMode = .newTaskStaging
            } else if case .task(let taskID) = route {
                outputURL = try taskService.makeCaptureOutputURL(taskId: taskID)
                outputMode = .existingTask(taskId: taskID)
            } else if let selectedTaskID {
                outputURL = try taskService.makeCaptureOutputURL(taskId: selectedTaskID)
                outputMode = .existingTask(taskId: selectedTaskID)
            } else {
                errorMessage = "No task selected for capture."
                overlayService.hideBorder()
                recordingControlOverlayService.hideRecordingHint()
                userInterruptionMonitor.stop()
                restoreAppWindowsAfterCaptureIfNeeded()
                return
            }
        } catch {
            isCapturing = false
            captureStartedAt = nil
            overlayService.hideBorder()
            recordingControlOverlayService.hideRecordingHint()
            userInterruptionMonitor.stop()
            restoreAppWindowsAfterCaptureIfNeeded()
            errorMessage = "Failed to start capture."
            return
        }

        isCapturing = true
        captureStartedAt = Date()
        captureOutputURL = outputURL
        captureOutputMode = outputMode
        errorMessage = nil

        // Launch capture off-main so overlay/window changes render immediately.
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try self.captureService.startCapture(
                    outputURL: outputURL,
                    displayID: captureDisplayIndex,
                    audioInput: requestedAudioInput
                )

                await MainActor.run {
                    // If we didn't hide early (permission prompt path), hide now once capture is running.
                    if didStartMonitor, self.captureHiddenWindows.isEmpty {
                        self.hideAppWindowsForCapture()
                    }

                    if self.captureService.lastCaptureIncludesMicrophone,
                       let warning = self.captureService.lastCaptureStartWarning {
                        self.recordingStatusMessage = "Capture started on Display \(captureDisplayIndex) with microphone audio. \(warning)"
                    } else if self.captureService.lastCaptureIncludesMicrophone {
                        self.recordingStatusMessage = "Capture started on Display \(captureDisplayIndex) with audio input: \(self.selectedAudioInputLabel)."
                    } else if let warning = self.captureService.lastCaptureStartWarning {
                        self.recordingStatusMessage = "Capture started on Display \(captureDisplayIndex) without microphone audio. \(warning)"
                    } else if requestedAudioInput == .none {
                        self.recordingStatusMessage = "Capture started on Display \(captureDisplayIndex) without microphone audio."
                    } else {
                        self.recordingStatusMessage = "Capture started on Display \(captureDisplayIndex)."
                    }
                }
            } catch let error as RecordingCaptureError {
                await MainActor.run {
                    self.isCapturing = false
                    self.captureStartedAt = nil
                    self.captureOutputURL = nil
                    self.captureOutputMode = nil
                    self.overlayService.hideBorder()
                    self.recordingControlOverlayService.hideRecordingHint()
                    self.userInterruptionMonitor.stop()
                    self.restoreAppWindowsAfterCaptureIfNeeded()

                    switch error {
                    case .permissionDenied:
                        self.errorMessage = "Screen Recording permission denied. Grant access in System Settings and retry."
                    case .alreadyCapturing:
                        self.errorMessage = "Capture is already running."
                    case .failedToStart(let reason):
                        self.errorMessage = "Failed to start capture: \(reason)"
                    default:
                        self.errorMessage = "Failed to start capture."
                    }
                }
            } catch {
                await MainActor.run {
                    self.isCapturing = false
                    self.captureStartedAt = nil
                    self.captureOutputURL = nil
                    self.captureOutputMode = nil
                    self.overlayService.hideBorder()
                    self.recordingControlOverlayService.hideRecordingHint()
                    self.userInterruptionMonitor.stop()
                    self.restoreAppWindowsAfterCaptureIfNeeded()
                    self.errorMessage = "Failed to start capture."
                }
            }
        }
    }

    private func handleUserInterruptionDuringCapture() {
        guard isCapturing else {
            return
        }
        // Event taps can call us off-main; UI state changes and sheet presentation must be on main.
        DispatchQueue.main.async { [weak self] in
            self?.stopCapture()
        }
    }

    private func hideAppWindowsForCapture() {
        // Hide the main UI windows so recording starts with a clear desktop.
        // Keep overlay windows (border + HUD) visible.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.hideAppWindowsForCapture()
            }
            return
        }

        // Only snapshot/hide once per capture session.
        guard captureHiddenWindows.isEmpty else { return }

        capturePreviouslyKeyWindow = NSApplication.shared.keyWindow

        var hidden: [CaptureHiddenWindow] = []
        for window in NSApplication.shared.windows {
            guard window.isVisible else { continue }
            // Only hide "normal" app UI windows. Keep overlays (statusBar+).
            if let id = window.identifier?.rawValue, id.hasPrefix("cc.overlay.") {
                continue
            }
            guard window.level.rawValue < NSWindow.Level.statusBar.rawValue else { continue }

            if window.styleMask.contains(.miniaturizable) {
                hidden.append(CaptureHiddenWindow(window: window, mode: .miniaturized))
                window.miniaturize(nil)
            } else {
                hidden.append(CaptureHiddenWindow(window: window, mode: .orderedOut))
                window.orderOut(nil)
            }
        }

        captureHiddenWindows = hidden
    }

    private func restoreAppWindowsAfterCaptureIfNeeded() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.restoreAppWindowsAfterCaptureIfNeeded()
            }
            return
        }

        guard !captureHiddenWindows.isEmpty else { return }

        let hidden = captureHiddenWindows
        captureHiddenWindows = []

        // Restore hidden windows first.
        for entry in hidden {
            switch entry.mode {
            case .miniaturized:
                if entry.window.isMiniaturized {
                    entry.window.deminiaturize(nil)
                }
            case .orderedOut:
                if !entry.window.isVisible {
                    entry.window.orderFront(nil)
                }
            }
        }

        // Bring the app back, matching the Stop button behavior when the UI is visible.
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Re-focus whichever window was key before we hid the UI, if it still exists.
        if let key = capturePreviouslyKeyWindow {
            key.makeKeyAndOrderFront(nil)
        } else if let anyUIWindow = hidden.first(where: { $0.window.level.rawValue < NSWindow.Level.statusBar.rawValue })?.window {
            anyUIWindow.makeKeyAndOrderFront(nil)
        }
        capturePreviouslyKeyWindow = nil
    }

    func stopCapture() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.stopCapture()
            }
            return
        }

        recordingControlOverlayService.hideRecordingHint()
        userInterruptionMonitor.stop()
        recordingStatusMessage = "Stopping capture..."
        errorMessage = nil

        let outputURL = captureOutputURL
        let outputMode = captureOutputMode
        captureOutputURL = nil
        captureOutputMode = nil

        // Stop capture off-main: `screencapture` finalization can take a moment and should not freeze UI.
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try self.captureService.stopCapture()
                await MainActor.run {
                    self.isCapturing = false
                    self.captureStartedAt = nil
                    self.overlayService.hideBorder()
                    self.finishedRecordingDidCreateTask = false

                    let resolvedMode: FinishedRecordingReview.Mode
                    if let outputMode {
                        resolvedMode = outputMode
                    } else if self.route == .newTask {
                        resolvedMode = .newTaskStaging
                    } else if case .task(let taskID) = self.route {
                        resolvedMode = .existingTask(taskId: taskID)
                    } else if let selectedTaskID = self.selectedTaskID {
                        resolvedMode = .existingTask(taskId: selectedTaskID)
                    } else {
                        resolvedMode = .newTaskStaging
                    }

                    // Make sure the window is restored before presenting the sheet.
                    self.restoreAppWindowsAfterCaptureIfNeeded()

                    switch resolvedMode {
                    case .newTaskStaging:
                        if let outputURL, let record = self.makeRecordingRecordFromFileURL(outputURL) {
                            self.recordingStatusMessage = "Capture stopped. Saved \(record.fileName)."
                            let review = FinishedRecordingReview(recording: record, mode: .newTaskStaging)
                            // Defer one tick to avoid presentation races with window restore.
                            DispatchQueue.main.async { [weak self] in
                                self?.finishedRecordingReview = review
                                self?.lastPresentedFinishedRecordingReview = review
                            }
                        } else {
                            self.recordingStatusMessage = "Capture stopped."
                        }
                    case .existingTask(let taskId):
                        self.loadSelectedTaskRecordings()
                        if let latest = self.recordings.first {
                            self.recordingStatusMessage = "Capture stopped. Saved \(latest.fileName)."
                            let review = FinishedRecordingReview(recording: latest, mode: .existingTask(taskId: taskId))
                            DispatchQueue.main.async { [weak self] in
                                self?.finishedRecordingReview = review
                                self?.lastPresentedFinishedRecordingReview = review
                            }
                        } else {
                            self.recordingStatusMessage = "Capture stopped."
                        }
                    }

                    self.errorMessage = nil
                }
            } catch RecordingCaptureError.notCapturing {
                await MainActor.run {
                    self.isCapturing = false
                    self.captureStartedAt = nil
                    self.overlayService.hideBorder()
                    self.restoreAppWindowsAfterCaptureIfNeeded()
                    self.errorMessage = "No active capture to stop."
                }
            } catch RecordingCaptureError.failedToStop(let reason) {
                await MainActor.run {
                    self.isCapturing = false
                    self.captureStartedAt = nil
                    self.overlayService.hideBorder()
                    self.restoreAppWindowsAfterCaptureIfNeeded()
                    self.errorMessage = "Failed to stop capture: \(reason)"
                }
            } catch {
                await MainActor.run {
                    self.isCapturing = false
                    self.captureStartedAt = nil
                    self.overlayService.hideBorder()
                    self.restoreAppWindowsAfterCaptureIfNeeded()
                    self.errorMessage = "Failed to stop capture."
                }
            }
        }
    }

    func handleFinishedRecordingSheetDismissed() {
        // If the user dismisses the sheet without taking an action, treat it as "nothing happened"
        // for New Task recordings: discard the staged capture and do not create a task.
        defer {
            finishedRecordingDidCreateTask = false
            lastPresentedFinishedRecordingReview = nil
        }

        guard let last = lastPresentedFinishedRecordingReview else {
            return
        }
        if case .newTaskStaging = last.mode, !finishedRecordingDidCreateTask {
            try? FileManager.default.removeItem(at: last.recording.fileURL)
        }
    }

    func recordAgainFromFinishedRecordingDialog() {
        guard let review = finishedRecordingReview else {
            return
        }
        if case .newTaskStaging = review.mode {
            try? FileManager.default.removeItem(at: review.recording.fileURL)
        }
        finishedRecordingReview = nil

        // Start a new capture on the next run loop turn so the sheet has time to dismiss.
        DispatchQueue.main.async { [weak self] in
            self?.startCapture()
        }
    }

    func extractTaskFromFinishedRecordingDialog() {
        guard let review = finishedRecordingReview else {
            return
        }
        guard requireProviderKey(for: .gemini, action: .extractTask) else {
            extractionStatusMessage = nil
            return
        }
        guard !isExtractingTask else {
            return
        }

        switch review.mode {
        case .existingTask(let taskId):
            Task { [weak self] in
                guard let self else { return }
                await MainActor.run {
                    self.selectedTaskID = taskId
                    self.openTask(taskId)
                }
                await self.extractTask(from: review.recording)
                await MainActor.run {
                    self.finishedRecordingReview = nil
                }
            }
        case .newTaskStaging:
            Task { [weak self] in
                await self?.extractAndCreateTaskFromStagedRecording(review.recording)
            }
        }
    }

    private func extractAndCreateTaskFromStagedRecording(_ recording: RecordingRecord) async {
        guard requireProviderKey(for: .gemini, action: .extractTask) else {
            await MainActor.run {
                extractionStatusMessage = nil
            }
            return
        }
        guard !isExtractingTask else {
            return
        }

        await MainActor.run {
            isExtractingTask = true
            extractingRecordingID = recording.id
            extractionStatusMessage = "Extracting task from recording..."
            errorMessage = nil
        }

        defer {
            Task { @MainActor [weak self] in
                self?.isExtractingTask = false
                self?.extractingRecordingID = nil
            }
        }

        do {
            let result = try await taskExtractionService.extractHeartbeatMarkdown(from: recording.fileURL)
            guard result.taskDetected else {
                await MainActor.run { [weak self] in
                    self?.extractionStatusMessage = "No actionable task detected. Nothing was created."
                    self?.errorMessage = nil
                }
                return
            }

            let derivedTitle = deriveTaskTitle(from: result.heartbeatMarkdown)
            let normalizedHeartbeat = normalizeExtractedHeartbeat(result.heartbeatMarkdown, title: derivedTitle)
            let task = try taskService.createTask(title: derivedTitle)
            _ = try taskService.attachRecordingFile(
                taskId: task.id,
                sourceURL: recording.fileURL,
                deleteSourceAfterCopy: true
            )
            try taskService.saveHeartbeat(taskId: task.id, markdown: normalizedHeartbeat)

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.finishedRecordingDidCreateTask = true
                self.selectedTaskID = task.id
                self.reloadTasks()
                self.openTask(task.id)
                self.loadSelectedTaskHeartbeat()
                self.loadSelectedTaskRecordings()
                    self.extractionStatusMessage = "Extraction complete (\(result.llm), \(result.promptVersion))."
                    self.errorMessage = nil
                    self.llmUserFacingIssue = nil
                    self.finishedRecordingReview = nil
                }
            } catch TaskExtractionServiceError.invalidModelOutput {
                await MainActor.run { [weak self] in
                    self?.extractionStatusMessage = nil
                    self?.errorMessage = "Extraction output was invalid. Nothing was created."
                    self?.llmUserFacingIssue = nil
                }
            } catch let error as GeminiLLMClientError {
                await MainActor.run { [weak self] in
                    self?.extractionStatusMessage = nil
                    if case .userFacingIssue(let issue) = error {
                        self?.llmUserFacingIssue = issue
                        self?.errorMessage = issue.userMessage
                    } else {
                        self?.llmUserFacingIssue = nil
                        self?.errorMessage = error.errorDescription ?? "Gemini request failed."
                    }
                }
            } catch LLMClientError.notConfigured {
                await MainActor.run { [weak self] in
                    self?.extractionStatusMessage = nil
                    self?.errorMessage = "Task extraction LLM client is not configured yet."
                    self?.llmUserFacingIssue = nil
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.extractionStatusMessage = nil
                    self?.errorMessage = "Failed to extract task from recording."
                    self?.llmUserFacingIssue = nil
                }
            }
        }

    private func deriveTaskTitle(from heartbeatMarkdown: String) -> String {
        let lines = heartbeatMarkdown.components(separatedBy: .newlines)
        guard let taskHeaderIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "# Task" }) else {
            return "Untitled Task"
        }
        for line in lines.dropFirst(taskHeaderIndex + 1) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("## ") { break }
            if let parsed = parseTitleLine(trimmed) {
                return parsed
            }
            // Keep titles compact and file-name safe-ish (TaskService will still create UUID workspace).
            if trimmed.count > 80 {
                return String(trimmed.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return trimmed
        }
        return "Untitled Task"
    }

    private func parseTitleLine(_ trimmedLine: String) -> String? {
        // Prefer the explicit Title field when the extraction prompt includes one.
        let lower = trimmedLine.lowercased()
        guard lower.hasPrefix("title:") else {
            return nil
        }
        let value = trimmedLine.dropFirst("title:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func normalizeExtractedHeartbeat(_ markdown: String, title: String) -> String {
        // Make the first non-empty line after `# Task` be a plain title (not `Title: ...`),
        // so the task list shows clean titles and the HEARTBEAT header reads well.
        var lines = markdown.components(separatedBy: .newlines)
        guard let taskHeaderIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "# Task" }) else {
            return markdown
        }

        var i = taskHeaderIndex + 1
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                i += 1
                continue
            }
            if trimmed.hasPrefix("## ") {
                break
            }
            if parseTitleLine(trimmed) != nil {
                lines[i] = title
            }
            break
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeRecordingRecordFromFileURL(_ url: URL) -> RecordingRecord? {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
        let size = Int64(values?.fileSize ?? 0)
        guard size > 0 else { return nil }

        return RecordingRecord(
            id: url.lastPathComponent,
            fileName: url.lastPathComponent,
            addedAt: values?.creationDate ?? Date(),
            fileURL: url,
            fileSizeBytes: size
        )
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
        case .gemini:
            providerSetupState.hasGeminiKey = saved
        }
    }

    private func providerDisplayName(_ provider: ProviderIdentifier) -> String {
        switch provider {
        case .openAI:
            return "OpenAI"
        case .gemini:
            return "Gemini"
        }
    }

    private func requireProviderKey(for provider: ProviderIdentifier, action: MissingProviderKeyDialog.Action) -> Bool {
        refreshProviderKeysState()
        guard apiKeyStore.hasKey(for: provider) else {
            missingProviderKeyDialog = MissingProviderKeyDialog(provider: provider, action: action)
            return false
        }
        return true
    }

    private func ensureRecordingPreflightRequirements() -> Bool {
        let missing = missingRecordingPreflightRequirements()
        guard !missing.isEmpty else {
            recordingPreflightDialogState = nil
            return true
        }
        recordingPreflightDialogState = RecordingPreflightDialogState(missingRequirements: missing)
        recordingStatusMessage = nil
        return false
    }

    private func ensureRunTaskPreflightRequirements() -> Bool {
        let missing = missingRunTaskPreflightRequirements()
        guard !missing.isEmpty else {
            runTaskPreflightDialogState = nil
            return true
        }
        runTaskPreflightDialogState = RunTaskPreflightDialogState(missingRequirements: missing)
        runStatusMessage = nil
        return false
    }

    private func refreshRecordingPreflightDialogState() {
        let missing = missingRecordingPreflightRequirements()
        if missing.isEmpty {
            recordingPreflightDialogState = nil
        } else {
            recordingPreflightDialogState = RecordingPreflightDialogState(missingRequirements: missing)
        }
    }

    private func refreshRunTaskPreflightDialogState() {
        let missing = missingRunTaskPreflightRequirements()
        if missing.isEmpty {
            runTaskPreflightDialogState = nil
        } else {
            runTaskPreflightDialogState = RunTaskPreflightDialogState(missingRequirements: missing)
        }
    }

    private func missingRecordingPreflightRequirements() -> [RecordingPreflightRequirement] {
        refreshProviderKeysState()

        var missing: [RecordingPreflightRequirement] = []
        if !apiKeyStore.hasKey(for: .gemini) {
            missing.append(.geminiAPIKey)
        }

        if permissionService.currentStatus(for: .screenRecording) != .granted {
            missing.append(.screenRecording)
        }
        if permissionService.currentStatus(for: .microphone) != .granted {
            missing.append(.microphone)
        }

        return missing
    }

    private func missingRunTaskPreflightRequirements() -> [RunTaskPreflightRequirement] {
        refreshProviderKeysState()

        var missing: [RunTaskPreflightRequirement] = []
        if !apiKeyStore.hasKey(for: .openAI) {
            missing.append(.openAIAPIKey)
        }
        if permissionService.currentStatus(for: .accessibility) != .granted {
            missing.append(.accessibility)
        }
        return missing
    }
}

private final class LLMCallRecorder {
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

private final class LLMScreenshotRecorder {
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

private final class ExecutionTraceRecorder {
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
