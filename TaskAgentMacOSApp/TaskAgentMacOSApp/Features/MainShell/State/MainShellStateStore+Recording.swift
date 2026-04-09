import Foundation
import AppKit
import CoreGraphics
import UniformTypeIdentifiers

extension MainShellStateStore {
    // MARK: - Recording

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

    func uploadRecordingForNewTask() {
        guard !isCapturing else {
            errorMessage = "Stop the current recording before uploading."
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Upload Recording"
        panel.prompt = "Upload"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        _ = importRecordingForNewTask(from: selectedURL)
    }

    @discardableResult
    func importRecordingForNewTask(from sourceURL: URL) -> Bool {
        guard !isCapturing else {
            errorMessage = "Stop the current recording before uploading."
            return false
        }

        let ext = sourceURL.pathExtension.lowercased()
        guard ext == "mp4" || ext == "mov" else {
            errorMessage = "Only .mp4 or .mov recordings are supported."
            return false
        }

        do {
            let baseStagingURL = try taskService.makeStagingCaptureOutputURL()
            let stagingURL = baseStagingURL
                .deletingPathExtension()
                .appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: stagingURL.path) {
                try FileManager.default.removeItem(at: stagingURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: stagingURL)

            guard let record = makeRecordingRecordFromFileURL(stagingURL) else {
                try? FileManager.default.removeItem(at: stagingURL)
                errorMessage = "Uploaded recording is empty or unreadable."
                return false
            }

            selectedTaskID = nil
            route = .newTask
            recordingStatusMessage = "Uploaded \(record.fileName)."
            extractionStatusMessage = nil
            errorMessage = nil

            let review = FinishedRecordingReview(recording: record, mode: .newTaskStaging)
            finishedRecordingReview = review
            lastPresentedFinishedRecordingReview = review
            finishedRecordingDidCreateTask = false
            return true
        } catch TaskServiceError.recordingTooLarge {
            errorMessage = "Recording is too large (max 2 GB)."
        } catch {
            errorMessage = "Failed to upload recording."
        }

        return false
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
}
