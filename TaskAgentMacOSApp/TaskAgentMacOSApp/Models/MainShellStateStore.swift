import Foundation
import Observation
import AppKit

@Observable
final class MainShellStateStore {
    private let taskService: TaskService
    private let taskExtractionService: TaskExtractionService
    private let heartbeatQuestionService: HeartbeatQuestionService
    private let automationEngine: any AutomationEngine
    private let apiKeyStore: any APIKeyStore
    private let permissionService: any PermissionService
    private let captureService: any RecordingCaptureService
    private let overlayService: any RecordingOverlayService
    private let agentControlOverlayService: any AgentControlOverlayService
    private let userInterruptionMonitor: any UserInterruptionMonitor
    private let agentCursorPresentationService: any AgentCursorPresentationService
    private let prepareDesktopForRun: @MainActor () -> Int
    private let llmCallRecorder: LLMCallRecorder
    private let llmScreenshotRecorder: LLMScreenshotRecorder
    private let executionTraceRecorder: ExecutionTraceRecorder
    private var runTaskHandle: Task<Void, Never>?

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
    var isRunningTask: Bool
    var saveStatusMessage: String?
    var recordingStatusMessage: String?
    var extractionStatusMessage: String?
    var runStatusMessage: String?
    var clarificationStatusMessage: String?
    var apiKeyStatusMessage: String?
    var apiKeyErrorMessage: String?
    var errorMessage: String?
    var llmCallLog: [LLMCallLogEntry]
    var llmScreenshotLog: [LLMScreenshotLogEntry]
    var executionTrace: [ExecutionTraceEntry]
    var isCapturingDiagnosticScreenshot: Bool
    var diagnosticScreenshotStatusMessage: String?
    var diagnosticTraceStatusMessage: String?
    var lastDiagnosticScreenshotPNGData: Data?
    var lastDiagnosticScreenshotWidth: Int?
    var lastDiagnosticScreenshotHeight: Int?

    init(
        taskService: TaskService = TaskService(),
        taskExtractionService: TaskExtractionService? = nil,
        heartbeatQuestionService: HeartbeatQuestionService = HeartbeatQuestionService(),
        automationEngine: (any AutomationEngine)? = nil,
        apiKeyStore: any APIKeyStore = KeychainAPIKeyStore(),
        permissionService: any PermissionService = MacPermissionService(),
        captureService: any RecordingCaptureService = ShellRecordingCaptureService(),
        overlayService: any RecordingOverlayService = ScreenRecordingOverlayService(),
        agentControlOverlayService: any AgentControlOverlayService = HUDWindowAgentControlOverlayService(),
        userInterruptionMonitor: any UserInterruptionMonitor = QuartzUserInterruptionMonitor(),
        agentCursorPresentationService: any AgentCursorPresentationService = AccessibilityAgentCursorPresentationService(),
        prepareDesktopForRun: @escaping @MainActor () -> Int = MainShellStateStore.prepareDesktopByHidingRunningApps
    ) {
        let callRecorder = LLMCallRecorder(maxEntries: 200)
        let screenshotRecorder = LLMScreenshotRecorder(maxEntries: 120)
        let traceRecorder = ExecutionTraceRecorder(maxEntries: 400)
        self.taskService = taskService
        self.apiKeyStore = apiKeyStore
        self.permissionService = permissionService
        self.taskExtractionService = taskExtractionService ?? TaskExtractionService(
            llmClient: GeminiVideoLLMClient(apiKeyStore: apiKeyStore)
        )
        self.heartbeatQuestionService = heartbeatQuestionService
        let anthropicRunner = AnthropicComputerUseRunner(
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
                let excludedWindowNumber = agentControlOverlayService.windowNumberForScreenshotExclusion()
                return try AnthropicComputerUseRunner.captureMainDisplayScreenshot(excludingWindowNumber: excludedWindowNumber)
            }
        )
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
                let excludedWindowNumber = agentControlOverlayService.windowNumberForScreenshotExclusion()
                return try OpenAIComputerUseRunner.captureMainDisplayScreenshot(excludingWindowNumber: excludedWindowNumber)
            }
        )

        let routedEngine = ProviderRoutingAutomationEngine(
            apiKeyStore: apiKeyStore,
            openAIEngine: OpenAIAutomationEngine(runner: openAIRunner),
            anthropicEngine: AnthropicAutomationEngine(runner: anthropicRunner)
        )

        self.automationEngine = automationEngine ?? routedEngine
        self.captureService = captureService
        self.overlayService = overlayService
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
        self.isRunningTask = false
        self.saveStatusMessage = nil
        self.recordingStatusMessage = nil
        self.extractionStatusMessage = nil
        self.runStatusMessage = nil
        self.clarificationStatusMessage = nil
        self.apiKeyStatusMessage = nil
        self.apiKeyErrorMessage = nil
        self.errorMessage = nil
        self.llmCallLog = []
        self.llmScreenshotLog = []
        self.executionTrace = []
        self.isCapturingDiagnosticScreenshot = false
        self.diagnosticScreenshotStatusMessage = nil
        self.diagnosticTraceStatusMessage = nil
        self.lastDiagnosticScreenshotPNGData = nil
        self.lastDiagnosticScreenshotWidth = nil
        self.lastDiagnosticScreenshotHeight = nil

        callRecorder.onRecord = { [weak self] _ in
            DispatchQueue.main.async {
                self?.llmCallLog = callRecorder.snapshot()
            }
        }

        screenshotRecorder.onRecord = { [weak self] _ in
            DispatchQueue.main.async {
                self?.llmScreenshotLog = screenshotRecorder.snapshot()
            }
        }

        traceRecorder.onRecord = { [weak self] _ in
            DispatchQueue.main.async {
                self?.executionTrace = traceRecorder.snapshot()
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

    func clearLLMCallLog() {
        llmCallRecorder.clear()
        llmCallLog = []
    }

    func clearLLMScreenshotLog() {
        llmScreenshotRecorder.clear()
        llmScreenshotLog = []
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
        selectedTaskID = taskID
        clarificationAnswerDraft = ""
        clarificationStatusMessage = nil
        runStatusMessage = nil
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

    func startRunTaskNow() {
        guard let selectedTaskID else {
            return
        }
        guard !isRunningTask else {
            return
        }

        guard ensureExecutionPermissions() else {
            return
        }

        let hiddenAppsCount = prepareDesktopForRun()
        executionTraceRecorder.record(
            ExecutionTraceEntry(kind: .info, message: "Prepared screen by hiding \(hiddenAppsCount) running app(s).")
        )

        isRunningTask = true
        runStatusMessage = "Running task..."
        errorMessage = nil
        let startedAt = Date()

        executionTraceRecorder.record(ExecutionTraceEntry(kind: .info, message: "Run requested for task \(selectedTaskID)."))
        agentControlOverlayService.showAgentInControl()
        if agentCursorPresentationService.activateTakeoverCursor() {
            executionTraceRecorder.record(ExecutionTraceEntry(kind: .info, message: "Increased cursor size during agent takeover."))
        } else {
            executionTraceRecorder.record(ExecutionTraceEntry(kind: .error, message: "Failed to increase cursor size during agent takeover."))
        }

        let didStartMonitor = userInterruptionMonitor.start { [weak self] in
            self?.handleUserInterruptionDuringRun()
        }
        if !didStartMonitor {
            agentControlOverlayService.hideAgentInControl()
            if !agentCursorPresentationService.deactivateTakeoverCursor() {
                executionTraceRecorder.record(ExecutionTraceEntry(kind: .error, message: "Failed to restore cursor size after takeover monitor startup failed."))
            }
            isRunningTask = false
            runStatusMessage = nil
            errorMessage =
                "Failed to start escape-key monitoring. To ensure the agent can be stopped via Escape, enable TaskAgentMacOSApp in System Settings > Privacy & Security > Input Monitoring (and Accessibility)."
            executionTraceRecorder.record(ExecutionTraceEntry(kind: .error, message: "Failed to start user-interruption monitor."))
            return
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

    func runTaskNow() async {
        guard let selectedTaskID else {
            return
        }
        guard !isRunningTask else {
            return
        }

        guard ensureExecutionPermissions() else {
            return
        }

        let hiddenAppsCount = prepareDesktopForRun()
        executionTraceRecorder.record(
            ExecutionTraceEntry(kind: .info, message: "Prepared screen by hiding \(hiddenAppsCount) running app(s).")
        )

        isRunningTask = true
        runStatusMessage = "Running task..."
        errorMessage = nil
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
        userInterruptionMonitor.stop()
        if !agentCursorPresentationService.deactivateTakeoverCursor() {
            executionTraceRecorder.record(ExecutionTraceEntry(kind: .error, message: "Failed to restore cursor size after cancellation request."))
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
        userInterruptionMonitor.stop()
        if !agentCursorPresentationService.deactivateTakeoverCursor() {
            executionTraceRecorder.record(ExecutionTraceEntry(kind: .error, message: "Failed to restore cursor size after run completion."))
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

        if result.outcome != .cancelled, let resultError = result.errorMessage, !resultError.isEmpty {
            errorMessage = resultError
        }
    }

    private func handleUserInterruptionDuringRun() {
        guard isRunningTask else {
            return
        }

        agentControlOverlayService.hideAgentInControl()
        userInterruptionMonitor.stop()
        if !agentCursorPresentationService.deactivateTakeoverCursor() {
            executionTraceRecorder.record(ExecutionTraceEntry(kind: .error, message: "Failed to restore cursor size after Escape takeover."))
        }
        runStatusMessage = "Cancelling (Escape pressed)..."
        executionTraceRecorder.record(ExecutionTraceEntry(kind: .cancelled, message: "Escape pressed; cancelling run."))
        runTaskHandle?.cancel()
    }

    private func ensureExecutionPermissions() -> Bool {
        let screenRecording = permissionService.requestAccessIfNeeded(for: .screenRecording)
        if screenRecording != .granted {
            runStatusMessage = nil
            errorMessage = "Screen Recording permission is required to capture screenshots for the execution agent. Enable TaskAgentMacOSApp in System Settings > Privacy & Security > Screen Recording."
            executionTraceRecorder.record(ExecutionTraceEntry(kind: .error, message: "Missing Screen Recording permission."))
            permissionService.openSystemSettings(for: .screenRecording)
            return false
        }

        let accessibility = permissionService.requestAccessIfNeeded(for: .accessibility)
        if accessibility != .granted {
            runStatusMessage = nil
            errorMessage = "Accessibility permission is required to perform clicks and typing. Enable TaskAgentMacOSApp in System Settings > Privacy & Security > Accessibility."
            executionTraceRecorder.record(ExecutionTraceEntry(kind: .error, message: "Missing Accessibility permission."))
            permissionService.openSystemSettings(for: .accessibility)
            return false
        }

        let inputMonitoring = permissionService.requestAccessIfNeeded(for: .inputMonitoring)
        if inputMonitoring != .granted {
            runStatusMessage = nil
            errorMessage = "Input Monitoring permission is required to stop the agent when you take over. Enable TaskAgentMacOSApp in System Settings > Privacy & Security > Input Monitoring."
            executionTraceRecorder.record(ExecutionTraceEntry(kind: .error, message: "Missing Input Monitoring permission."))
            permissionService.openSystemSettings(for: .inputMonitoring)
            return false
        }

        return true
    }

    @MainActor
    private static func prepareDesktopByHidingRunningApps() -> Int {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        var hiddenCount = 0

        for app in NSWorkspace.shared.runningApplications {
            guard app.processIdentifier != currentPID else { continue }
            guard app.activationPolicy == .regular else { continue }
            guard !app.isHidden else { continue }
            if app.hide() {
                hiddenCount += 1
            }
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
