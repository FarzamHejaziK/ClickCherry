import Foundation

extension MainShellStateStore {
    // MARK: - Extraction

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
}
