import Foundation
import AppKit

extension MainShellStateStore {
    // MARK: - Preflight

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
        if finishedRecordingReview != nil {
            // User intentionally leaves the finished-recording flow to configure a key.
            // Avoid staged-file cleanup on this transition.
            finishedRecordingDidCreateTask = true
            finishedRecordingReview = nil
        }
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

    func requireProviderKey(for provider: ProviderIdentifier, action: MissingProviderKeyDialog.Action) -> Bool {
        refreshProviderKeysState()
        guard apiKeyStore.hasKey(for: provider) else {
            missingProviderKeyDialog = MissingProviderKeyDialog(provider: provider, action: action)
            return false
        }
        return true
    }

    func ensureRecordingPreflightRequirements() -> Bool {
        let missing = missingRecordingPreflightRequirements()
        guard !missing.isEmpty else {
            recordingPreflightDialogState = nil
            return true
        }
        recordingPreflightDialogState = RecordingPreflightDialogState(missingRequirements: missing)
        recordingStatusMessage = nil
        return false
    }

    func ensureRunTaskPreflightRequirements() -> Bool {
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
        if permissionService.currentStatus(for: .inputMonitoring) != .granted {
            missing.append(.inputMonitoring)
        }
        return missing
    }
}
