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
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.handleUserInterruptionDuringRun()
            }
            return
        }

        guard isRunningTask else {
            return
        }

        agentControlOverlayService.hideAgentInControl()
        overlayService.hideBorder()
        userInterruptionMonitor.stop()
        if !agentCursorPresentationService.deactivateTakeoverCursor() {
            executionTraceRecorder.record(ExecutionTraceEntry(kind: .error, message: "Failed to deactivate takeover cursor presentation after Escape takeover."))
        }
        revealAppAfterRunCancellation()
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
    }

    func appendScreenshotLogToActiveRun(_ entry: LLMScreenshotLogEntry) {
        guard let activeRunID else { return }
        var entries = runScreenshotLogByRunID[activeRunID] ?? []
        entries.append(entry)
        if entries.count > 40 {
            entries.removeFirst(entries.count - 40)
        }
        runScreenshotLogByRunID[activeRunID] = entries
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
}
