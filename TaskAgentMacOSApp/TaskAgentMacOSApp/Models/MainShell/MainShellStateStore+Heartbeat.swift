import Foundation

extension MainShellStateStore {
    // MARK: - Heartbeat

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
}
