import Foundation

extension MainShellStateStore {
    // MARK: - Navigation & Task List

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

    func selectTask(_ taskID: String?) {
        guard let taskID else {
            openNewTask()
            return
        }

        openTask(taskID)
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

    func resolvedDisplayOption(selectedID: Int?) -> CaptureDisplayOption? {
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

    static let pinnedTasksUserDefaultsKey = "tasks.pinned.ids"

    static func loadPinnedTaskIDs(from defaults: UserDefaults) -> Set<String> {
        let raw = defaults.array(forKey: pinnedTasksUserDefaultsKey) as? [String] ?? []
        return Set(raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
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
}
