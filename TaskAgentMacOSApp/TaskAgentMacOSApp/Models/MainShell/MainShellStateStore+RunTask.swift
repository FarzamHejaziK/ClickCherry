import Foundation
import AppKit

extension MainShellStateStore {
    // MARK: - Run Task

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

        guard ensureRunnerWindowedModeBeforeRun() else {
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
        refreshAgentControlOverlay()
        if agentCursorPresentationService.activateTakeoverCursor() {
            executionTraceRecorder.record(ExecutionTraceEntry(kind: .info, message: "Cursor presentation left unchanged during agent takeover."))
        } else {
            executionTraceRecorder.record(ExecutionTraceEntry(kind: .error, message: "Failed to activate takeover cursor presentation."))
        }

        let didStartMonitor = userInterruptionMonitor.start { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleUserInterruptionDuringRun()
            }
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

        guard ensureRunnerWindowedModeBeforeRun() else {
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
        overlayService.hideBorder()
        userInterruptionMonitor.stop()
        if !agentCursorPresentationService.deactivateTakeoverCursor() {
            executionTraceRecorder.record(ExecutionTraceEntry(kind: .error, message: "Failed to deactivate takeover cursor presentation after cancellation request."))
        }
        activeRunOverlayPhase = .stopping
        activeRunOverlayStopReason = nil
        refreshAgentControlOverlay()
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
        activeRunOverlayPhase = .running
        activeRunOverlayStopReason = nil
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
                let screenshots = runScreenshotLogByRunID[finished.id] ?? []
                _ = try taskService.saveAgentRunScreenshots(taskId: taskId, run: finished, screenshots: screenshots)
                let exchanges = runLLMExchangeLogByRunID[finished.id] ?? []
                _ = try taskService.saveAgentRunLLMExchanges(taskId: taskId, run: finished, exchanges: exchanges)
            } catch {
                // Keep the run visible in-memory even if persistence fails.
                if errorMessage == nil {
                    errorMessage = "Task run finished but failed to persist run artifacts."
                }
            }
        }
    }

    @MainActor
    private func handleUserInterruptionDuringRun() {
        guard isRunningTask else {
            return
        }

        overlayService.hideBorder()
        userInterruptionMonitor.stop()
        if !agentCursorPresentationService.deactivateTakeoverCursor() {
            executionTraceRecorder.record(ExecutionTraceEntry(kind: .error, message: "Failed to deactivate takeover cursor presentation after Escape takeover."))
        }
        activeRunOverlayPhase = .stopping
        activeRunOverlayStopReason = "Escape pressed"
        refreshAgentControlOverlay()
        revealAppAfterRunCancellation()
        runStatusMessage = "Cancelling (Escape pressed)..."
        executionTraceRecorder.record(ExecutionTraceEntry(kind: .cancelled, message: "Escape pressed; cancelling run."))
        runTaskHandle?.cancel()
    }

    private func beginRun(displayIndex: Int) {
        let run = AgentRunRecord(startedAt: Date(), displayIndex: displayIndex)
        runHistory.insert(run, at: 0)
        runScreenshotLogByRunID[run.id] = []
        runLLMExchangeLogByRunID[run.id] = []
        activeRunID = run.id
        activeRunOverlayPhase = .running
        activeRunOverlayStopReason = nil
    }

    private func refreshAgentControlOverlay() {
        guard let activeRunID,
              let run = runHistory.first(where: { $0.id == activeRunID }) else {
            return
        }

        let rawNewestEvent = run.events.last
        let displayNewestEvent = rawNewestEvent.flatMap(overlayDisplayEvent)
        let recentEvents = Array(run.events.compactMap(overlayDisplayEvent).suffix(6).reversed())
        let recentScreenshots = Array((runScreenshotLogByRunID[activeRunID] ?? []).suffix(3).reversed())
        let newestScreenshot = recentScreenshots.first
        let latestActivityAt = [
            run.startedAt,
            rawNewestEvent?.timestamp ?? run.startedAt,
            newestScreenshot?.timestamp ?? run.startedAt
        ].max() ?? run.startedAt
        let activityState: AgentControlOverlayActivityState
        let headline: String

        switch activeRunOverlayPhase {
        case .running:
            activityState = overlayActivityState(
                newestEvent: rawNewestEvent,
                newestScreenshot: newestScreenshot
            )
            headline = displayNewestEvent?.message ?? overlayDefaultHeadline(for: activityState)
        case .stopping:
            headline = "Stopping agent…"
            activityState = .stopping
        }

        agentControlOverlayService.updateAgentInControl(
            snapshot: AgentControlOverlaySnapshot(
                headline: headline,
                stopReason: activeRunOverlayStopReason,
                events: recentEvents,
                screenshots: recentScreenshots,
                startedAt: run.startedAt,
                latestActivityAt: latestActivityAt,
                activityState: activityState
            ),
            phase: activeRunOverlayPhase
        )
    }

    private func overlayActivityState(
        newestEvent: AgentRunEvent?,
        newestScreenshot: LLMScreenshotLogEntry?
    ) -> AgentControlOverlayActivityState {
        if let newestScreenshot,
           newestScreenshot.timestamp >= (newestEvent?.timestamp ?? .distantPast) {
            return .capturing
        }

        guard let newestEvent else {
            return .starting
        }

        switch newestEvent.kind {
        case .llm, .info:
            return .thinking
        case .tool:
            return .usingTool
        case .action:
            return .acting
        case .completion:
            return .completing
        case .cancelled:
            return .stopping
        case .error:
            return .error
        }
    }

    private func overlayDefaultHeadline(for activityState: AgentControlOverlayActivityState) -> String {
        switch activityState {
        case .starting:
            return "Agent is running"
        case .thinking:
            return "Thinking through the next step"
        case .usingTool:
            return "Preparing the next action"
        case .acting:
            return "Working on the screen"
        case .capturing:
            return "Reviewing the screen"
        case .completing:
            return "Finishing the task"
        case .error:
            return "Ran into an issue while working"
        case .stopping:
            return "Stopping agent…"
        }
    }

    private func overlayDisplayEvent(_ event: AgentRunEvent) -> AgentRunEvent? {
        guard let message = overlayDisplayMessage(for: event) else {
            return nil
        }

        return AgentRunEvent(
            id: event.id,
            timestamp: event.timestamp,
            kind: event.kind,
            message: message
        )
    }

    private func overlayDisplayMessage(for event: AgentRunEvent) -> String? {
        switch event.kind {
        case .info:
            return nil
        case .llm:
            return "Thinking through the next step"
        case .tool, .action:
            return overlayActionMessage(from: event.message)
        case .completion:
            return "Finishing the task"
        case .cancelled:
            return "Stopping the agent"
        case .error:
            return overlayErrorMessage(from: event.message)
        }
    }

    private func overlayActionMessage(from message: String) -> String? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let lower = trimmed.lowercased()

        if lower.hasPrefix("opened ") {
            return "Opening \(trimmed.dropFirst("Opened ".count))"
        }
        if lower.hasPrefix("clicked ") {
            return "Clicking \(trimmed.dropFirst("Clicked ".count))"
        }
        if lower.hasPrefix("selected ") {
            return "Selecting \(trimmed.dropFirst("Selected ".count))"
        }
        if lower.hasPrefix("pressed ") {
            return "Pressing \(trimmed.dropFirst("Pressed ".count))"
        }
        if lower.hasPrefix("read cursor position") || lower.contains("cursor_position") {
            return "Checking the pointer position"
        }
        if lower.hasPrefix("move mouse to") || lower.contains(".mouse_move") || lower.contains(".move_mouse") || lower.contains(".move(") {
            return "Moving the pointer"
        }
        if lower.hasPrefix("right click at") || lower.contains(".right_click") {
            return "Opening a context menu"
        }
        if lower.hasPrefix("double click at") || lower.contains(".double_click") {
            return "Double-clicking on the screen"
        }
        if lower.hasPrefix("click at") || lower.contains(".left_click") {
            return "Clicking on the screen"
        }
        if lower.hasPrefix("type text ") || lower.contains(".type(") {
            return "Typing into the active field"
        }
        if lower.hasPrefix("press shortcut ") || lower.contains(".key(") {
            return "Using a keyboard shortcut"
        }
        if lower.hasPrefix("open app ") || lower.contains(".open_app(") {
            if let appName = overlayQuotedValue(in: trimmed) {
                return "Opening \(appName)"
            }
            return "Opening an app"
        }
        if lower.hasPrefix("open url ") || lower.contains(".open_url(") {
            if let destination = overlayURLLabel(in: trimmed) {
                return "Opening \(destination)"
            }
            return "Opening a page"
        }
        if lower.hasPrefix("scroll ") || lower.contains(".scroll") {
            return "Scrolling the page"
        }
        if lower.hasPrefix("wait ") || lower.contains(".wait") {
            return "Waiting for the screen to settle"
        }
        if lower.hasPrefix("capture full screenshot") {
            return "Reviewing the screen"
        }
        if lower.hasPrefix("capture current screenshot view") {
            return "Reviewing the current view"
        }
        if lower.hasPrefix("capture crop screenshot") || (lower.contains(".screenshot(") && lower.contains("mode=crop")) {
            return "Inspecting part of the screen"
        }
        if lower.contains(".screenshot(") {
            return "Reviewing the screen"
        }
        if lower.hasPrefix("terminal exec:") || lower.hasPrefix("terminal_exec(") {
            return "Running a terminal command"
        }
        if lower.hasPrefix("turn ") {
            return "Thinking through the next step"
        }
        if overlayShouldHideBackendMessage(trimmed) {
            return nil
        }
        return trimmed
    }

    private func overlayErrorMessage(from message: String) -> String? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let lower = trimmed.lowercased()
        if lower.contains("transport") || lower.contains("websocket") || lower.contains("http") || lower.contains("https") || lower.contains("connection") || lower.contains("network") {
            return "Hit a connection issue while working"
        }
        if lower.contains("permission") || lower.contains("screen recording") || lower.contains("accessibility") || lower.contains("input monitoring") {
            return "Ran into a permissions issue"
        }
        if lower.contains("cursor presentation") || lower.contains("run display") || lower.contains("prepared screen") || lower.contains("fullscreen") {
            return nil
        }
        return "Ran into an issue while working"
    }

    private func overlayShouldHideBackendMessage(_ message: String) -> Bool {
        let lower = message.lowercased()
        let backendMarkers = [
            "function_call",
            "output types:",
            "completion payload:",
            "debug visual observation",
            "debug mouse location",
            "run display set to display",
            "prepared screen by hiding",
            "run requested for task",
            "cursor presentation",
            "fullscreen",
            "request id",
            "bytes sent",
            "bytes received",
            "provider",
            "transport",
            "websocket"
        ]
        return backendMarkers.contains { lower.contains($0) }
    }

    private func overlayQuotedValue(in message: String) -> String? {
        if let value = overlayQuotedValue(in: message, delimiter: "'") {
            return value
        }
        return overlayQuotedValue(in: message, delimiter: "\"")
    }

    private func overlayQuotedValue(in message: String, delimiter: Character) -> String? {
        guard let start = message.firstIndex(of: delimiter) else {
            return nil
        }
        let afterStart = message.index(after: start)
        guard let end = message[afterStart...].firstIndex(of: delimiter) else {
            return nil
        }
        let value = message[afterStart..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func overlayURLLabel(in message: String) -> String? {
        guard let rawValue = overlayQuotedValue(in: message) else {
            return nil
        }
        guard let url = URL(string: rawValue) else {
            return nil
        }
        let host = url.host?.replacingOccurrences(of: "www.", with: "")
        return host?.isEmpty == false ? host : "a page"
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

    func appendTraceEventToActiveRun(_ entry: ExecutionTraceEntry) {
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
        refreshAgentControlOverlay()
    }

    func appendLLMCallEventToActiveRun(_ entry: LLMCallLogEntry) {
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
        refreshAgentControlOverlay()
    }

    func appendScreenshotLogToActiveRun(_ entry: LLMScreenshotLogEntry) {
        guard let activeRunID else { return }
        var entries = runScreenshotLogByRunID[activeRunID] ?? []
        entries.append(entry)
        if entries.count > 40 {
            entries.removeFirst(entries.count - 40)
        }
        runScreenshotLogByRunID[activeRunID] = entries
        refreshAgentControlOverlay()
    }

    func appendLLMExchangeLogToActiveRun(_ entry: LLMExchangeLogEntry) {
        guard let activeRunID else { return }
        var entries = runLLMExchangeLogByRunID[activeRunID] ?? []
        entries.append(entry)
        if entries.count > 40 {
            entries.removeFirst(entries.count - 40)
        }
        runLLMExchangeLogByRunID[activeRunID] = entries
    }

    @MainActor
    static func prepareDesktopByHidingRunningApps() -> Int {
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

    @MainActor
    static func revealAppWindowsAfterRunCancellation() {
        var firstAppWindow: NSWindow?

        for window in NSApplication.shared.windows {
            if let id = window.identifier?.rawValue, id.hasPrefix("cc.overlay.") {
                continue
            }
            guard window.level.rawValue < NSWindow.Level.statusBar.rawValue else { continue }
            guard window.styleMask.contains(.titled) else { continue }

            if firstAppWindow == nil {
                firstAppWindow = window
            }

            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        firstAppWindow?.makeKeyAndOrderFront(nil)
    }

    @MainActor
    private func ensureRunnerWindowedModeBeforeRun() -> Bool {
        guard let fullscreenWindow = Self.findFullscreenWindowForRunPreparation() else {
            return true
        }

        executionTraceRecorder.record(
            ExecutionTraceEntry(kind: .info, message: "App is fullscreen; exiting fullscreen before run start.")
        )

        let didExit = Self.exitFullscreenWindowForRunPreparation(fullscreenWindow)
        if didExit {
            executionTraceRecorder.record(
                ExecutionTraceEntry(kind: .info, message: "Exited fullscreen mode; continuing run preparation.")
            )
            return true
        }

        executionTraceRecorder.record(
            ExecutionTraceEntry(
                kind: .error,
                message: "Could not exit fullscreen mode before run start within timeout."
            )
        )
        errorMessage = "Could not exit fullscreen mode before run start. Please leave fullscreen and try again."
        runStatusMessage = nil
        return false
    }

    @MainActor
    private static func findFullscreenWindowForRunPreparation() -> NSWindow? {
        NSApplication.shared.windows.first { window in
            guard window.isVisible else { return false }
            if let id = window.identifier?.rawValue, id.hasPrefix("cc.overlay.") {
                return false
            }
            return window.styleMask.contains(.fullScreen)
        }
    }

    @MainActor
    private static func exitFullscreenWindowForRunPreparation(_ window: NSWindow, timeoutSeconds: TimeInterval = 2.5) -> Bool {
        guard window.styleMask.contains(.fullScreen) else {
            return true
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if !window.styleMask.contains(.fullScreen) {
                return true
            }
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        return !window.styleMask.contains(.fullScreen)
    }
}
