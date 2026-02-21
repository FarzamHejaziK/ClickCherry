import SwiftUI

#if DEBUG

private enum PreviewFrames {
    static let `default` = CGSize(width: 1100, height: 720)
    static let recordingDialog = CGSize(width: 780, height: 560)
    static let extractionCanvas = CGSize(width: 780, height: 260)
    static let llmIssueCanvas = CGSize(width: 860, height: 270)
}

private final class PreviewAPIKeyStore: APIKeyStore {
    private var keys: [ProviderIdentifier: String] = [:]

    func hasKey(for provider: ProviderIdentifier) -> Bool {
        guard let key = keys[provider] else {
            return false
        }
        return !key.isEmpty
    }

    func readKey(for provider: ProviderIdentifier) throws -> String? {
        keys[provider]
    }

    func setKey(_ key: String?, for provider: ProviderIdentifier) throws {
        keys[provider] = key
    }
}

private final class PreviewOnboardingCompletionStore: OnboardingCompletionStore {
    var hasCompletedOnboarding: Bool

    init(hasCompletedOnboarding: Bool) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
}

private struct PreviewPermissionStatuses: Equatable {
    var screenRecording: PermissionGrantStatus = .notGranted
    var microphone: PermissionGrantStatus = .notGranted
    var accessibility: PermissionGrantStatus = .notGranted
    var inputMonitoring: PermissionGrantStatus = .notGranted
}

private struct PreviewPermissionService: PermissionService {
    var statuses: PreviewPermissionStatuses = PreviewPermissionStatuses()

    func openSystemSettings(for permission: AppPermission) {
        // No-op in previews.
    }

    func currentStatus(for permission: AppPermission) -> PermissionGrantStatus {
        switch permission {
        case .screenRecording:
            return statuses.screenRecording
        case .microphone:
            return statuses.microphone
        case .accessibility:
            return statuses.accessibility
        case .inputMonitoring:
            return statuses.inputMonitoring
        }
    }
}

private enum PreviewOnboardingFactory {
    static func store(
        currentStep: OnboardingStep = .welcome,
        hasCompletedOnboarding: Bool = false,
        providerSetupState: ProviderSetupState = ProviderSetupState(hasOpenAIKey: false, hasGeminiKey: false),
        permissionStatuses: PreviewPermissionStatuses = PreviewPermissionStatuses()
    ) -> OnboardingStateStore {
        OnboardingStateStore(
            keyStore: PreviewAPIKeyStore(),
            completionStore: PreviewOnboardingCompletionStore(hasCompletedOnboarding: hasCompletedOnboarding),
            permissionService: PreviewPermissionService(statuses: permissionStatuses),
            currentStep: currentStep,
            providerSetupState: providerSetupState,
            hasScreenRecordingPermission: permissionStatuses.screenRecording == .granted,
            hasMicrophonePermission: permissionStatuses.microphone == .granted,
            hasAccessibilityPermission: permissionStatuses.accessibility == .granted,
            hasInputMonitoringPermission: permissionStatuses.inputMonitoring == .granted,
            hasCompletedOnboarding: hasCompletedOnboarding
        )
    }
}

private enum PreviewMainShellFactory {
    static func newTaskStore() -> MainShellStateStore {
        let store = MainShellStateStore()
        store.openNewTask()
        return store
    }

    static func settingsStore() -> MainShellStateStore {
        let store = MainShellStateStore()
        store.openSettings()
        return store
    }

    static func taskDetailStore() -> MainShellStateStore {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent("clickcherry-preview-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: baseDir, withIntermediateDirectories: true)

        let taskService = TaskService(
            baseDir: baseDir,
            fileManager: fm,
            workspaceService: WorkspaceService(fileManager: fm)
        )
        let store = MainShellStateStore(
            taskService: taskService,
            apiKeyStore: PreviewAPIKeyStore()
        )

        if let task = try? taskService.createTask(title: "Submit Expense Reimbursement") {
            let heartbeat = """
            # Task
            Submit Expense Reimbursement

            Goal: Submit a reimbursement request in the company portal for a recent receipt.

            AppsObserved:
            - Google Chrome

            HardConstraints:
            - Do not submit if any required fields are missing.
            - Do not upload the wrong receipt.

            SuccessCriteria:
            - A reimbursement request is submitted and a confirmation page/ID is shown.

            ## Questions
            - [required] Which portal URL should I use?
            - [required] Which cost center should be used?
            """
            try? taskService.saveHeartbeat(taskId: task.id, markdown: heartbeat)

            store.reloadTasks()
            store.openTask(task.id)

            store.availableCaptureDisplays = [
                CaptureDisplayOption(id: 1001, label: "Display 1", screencaptureDisplayIndex: 1),
                CaptureDisplayOption(id: 1002, label: "Display 2", screencaptureDisplayIndex: 2)
            ]
            store.selectedRunDisplayID = 1001
            let now = Date()
            store.runHistory = [
                AgentRunRecord(
                    startedAt: now.addingTimeInterval(-120),
                    finishedAt: now.addingTimeInterval(-105),
                    outcome: .success,
                    displayIndex: 1,
                    events: [
                        AgentRunEvent(timestamp: now.addingTimeInterval(-119), kind: .info, message: "Run requested."),
                        AgentRunEvent(timestamp: now.addingTimeInterval(-118), kind: .llm, message: "openAI/execution OK 842ms (HTTP 200)"),
                        AgentRunEvent(timestamp: now.addingTimeInterval(-116), kind: .tool, message: "desktop_action.left_click (x=418, y=322)"),
                        AgentRunEvent(timestamp: now.addingTimeInterval(-115), kind: .action, message: "Click at (418, 322)"),
                        AgentRunEvent(timestamp: now.addingTimeInterval(-110), kind: .completion, message: "Run complete.")
                    ]
                ),
                AgentRunRecord(
                    startedAt: now.addingTimeInterval(-40),
                    finishedAt: now.addingTimeInterval(-22),
                    outcome: .cancelled,
                    displayIndex: 2,
                    events: [
                        AgentRunEvent(timestamp: now.addingTimeInterval(-39), kind: .info, message: "Run requested."),
                        AgentRunEvent(timestamp: now.addingTimeInterval(-36), kind: .llm, message: "openAI/execution OK 611ms (HTTP 200)"),
                        AgentRunEvent(timestamp: now.addingTimeInterval(-34), kind: .tool, message: "desktop_action.type (text=...)"),
                        AgentRunEvent(timestamp: now.addingTimeInterval(-33), kind: .action, message: "Typed into focused field."),
                        AgentRunEvent(timestamp: now.addingTimeInterval(-23), kind: .cancelled, message: "Escape pressed; cancelling run.")
                    ]
                )
            ]
        }

        return store
    }
}

private struct PreviewRootView: View {
    let onboardingStateStore: OnboardingStateStore?

    var body: some View {
        Group {
            if let onboardingStateStore {
                RootView(onboardingStateStore: onboardingStateStore)
            } else {
                RootView()
            }
        }
        .preferredColorScheme(.light)
    }
}

private struct PreviewMainShellView: View {
    let store: MainShellStateStore

    var body: some View {
        MainShellView(mainShellStateStore: store)
            .preferredColorScheme(.light)
    }
}

#Preview(
    "RootView (Default)",
    traits: .fixedLayout(width: PreviewFrames.default.width, height: PreviewFrames.default.height)
) {
    PreviewRootView(onboardingStateStore: nil)
}

#Preview(
    "Onboarding - Welcome",
    traits: .fixedLayout(width: PreviewFrames.default.width, height: PreviewFrames.default.height)
) {
    PreviewRootView(
        onboardingStateStore: PreviewOnboardingFactory.store(currentStep: .welcome, hasCompletedOnboarding: false)
    )
}

#Preview(
    "Onboarding - Provider Setup",
    traits: .fixedLayout(width: PreviewFrames.default.width, height: PreviewFrames.default.height)
) {
    PreviewRootView(
        onboardingStateStore: PreviewOnboardingFactory.store(currentStep: .providerSetup, hasCompletedOnboarding: false)
    )
}

#Preview(
    "Onboarding - Permissions",
    traits: .fixedLayout(width: PreviewFrames.default.width, height: PreviewFrames.default.height)
) {
    PreviewRootView(
        onboardingStateStore: PreviewOnboardingFactory.store(currentStep: .permissionsPreflight, hasCompletedOnboarding: false)
    )
}

#Preview(
    "Onboarding - Ready",
    traits: .fixedLayout(width: PreviewFrames.default.width, height: PreviewFrames.default.height)
) {
    PreviewRootView(
        onboardingStateStore: PreviewOnboardingFactory.store(
            currentStep: .ready,
            hasCompletedOnboarding: false,
            providerSetupState: ProviderSetupState(hasOpenAIKey: true, hasGeminiKey: true),
            permissionStatuses: PreviewPermissionStatuses(
                screenRecording: .granted,
                microphone: .granted,
                accessibility: .granted,
                inputMonitoring: .granted
            )
        )
    )
}

#Preview(
    "New Task (Default)",
    traits: .fixedLayout(width: PreviewFrames.default.width, height: PreviewFrames.default.height)
) {
    PreviewMainShellView(store: PreviewMainShellFactory.newTaskStore())
}

#Preview(
    "Settings (Default)",
    traits: .fixedLayout(width: PreviewFrames.default.width, height: PreviewFrames.default.height)
) {
    PreviewMainShellView(store: PreviewMainShellFactory.settingsStore())
}

#Preview(
    "Recording Finished Dialog",
    traits: .fixedLayout(width: PreviewFrames.recordingDialog.width, height: PreviewFrames.recordingDialog.height)
) {
    let recording = RecordingRecord(
        id: UUID().uuidString,
        fileName: "ClickCherry-Recording-Example.mov",
        addedAt: Date(),
        fileURL: URL(fileURLWithPath: "/tmp/clickcherry-preview-example.mov"),
        fileSizeBytes: 123_456_789
    )
    return RecordingFinishedDialogView(
        recording: recording,
        isExtracting: false,
        statusMessage: nil,
        errorMessage: nil,
        llmUserFacingIssue: nil,
        missingProviderKeyDialog: nil,
        onRecordAgain: {},
        onExtractTask: {},
        onDismissMissingProviderKeyDialog: {},
        onOpenSettingsForMissingProviderKeyDialog: {},
        onOpenSettingsForLLMIssue: {},
        onOpenProviderConsoleForLLMIssue: {}
    )
    .preferredColorScheme(.light)
}

#Preview(
    "Recording Finished Dialog (Extracting)",
    traits: .fixedLayout(width: PreviewFrames.recordingDialog.width, height: PreviewFrames.recordingDialog.height)
) {
    let recording = RecordingRecord(
        id: UUID().uuidString,
        fileName: "ClickCherry-Recording-Example.mov",
        addedAt: Date(),
        fileURL: URL(fileURLWithPath: "/tmp/clickcherry-preview-example.mov"),
        fileSizeBytes: 123_456_789
    )
    return RecordingFinishedDialogView(
        recording: recording,
        isExtracting: true,
        statusMessage: "Extracting task from ClickCherry-Recording-Example.mov...",
        errorMessage: nil,
        llmUserFacingIssue: nil,
        missingProviderKeyDialog: nil,
        onRecordAgain: {},
        onExtractTask: {},
        onDismissMissingProviderKeyDialog: {},
        onOpenSettingsForMissingProviderKeyDialog: {},
        onOpenSettingsForLLMIssue: {},
        onOpenProviderConsoleForLLMIssue: {}
    )
    .preferredColorScheme(.light)
}

#Preview(
    "Extraction Progress Canvas",
    traits: .fixedLayout(width: PreviewFrames.extractionCanvas.width, height: PreviewFrames.extractionCanvas.height)
) {
    ZStack {
        VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)

        TaskExtractionProgressCanvasView(
            title: "Extracting task from recording",
            detail: "Analyzing content and preparing HEARTBEAT.md"
        )
        .padding(24)
    }
    .preferredColorScheme(.light)
}

#Preview(
    "LLM Issue - Invalid Credentials",
    traits: .fixedLayout(width: PreviewFrames.llmIssueCanvas.width, height: PreviewFrames.llmIssueCanvas.height)
) {
    ZStack {
        VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
        LinearGradient(
            colors: [Color.accentColor.opacity(0.08), Color.clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        LLMUserFacingIssueCanvasView(
            issue: LLMUserFacingIssue(
                provider: .openAI,
                operation: .execution,
                kind: .invalidCredentials,
                providerMessage: "Incorrect API key provided: sk-... is invalid",
                httpStatus: 401,
                providerCode: "invalid_api_key",
                requestID: "req_preview_invalid_key"
            ),
            onOpenSettings: {},
            onOpenProviderConsole: {}
        )
        .padding(24)
    }
    .preferredColorScheme(.light)
}

#Preview(
    "LLM Issue - Rate Limited",
    traits: .fixedLayout(width: PreviewFrames.llmIssueCanvas.width, height: PreviewFrames.llmIssueCanvas.height)
) {
    ZStack {
        VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
        LinearGradient(
            colors: [Color.accentColor.opacity(0.08), Color.clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        LLMUserFacingIssueCanvasView(
            issue: LLMUserFacingIssue(
                provider: .openAI,
                operation: .execution,
                kind: .rateLimited,
                providerMessage: "Rate limit reached for requests per minute.",
                httpStatus: 429,
                providerCode: "rate_limit_exceeded",
                requestID: "req_preview_rate_limit"
            ),
            onOpenSettings: {},
            onOpenProviderConsole: {}
        )
        .padding(24)
    }
    .preferredColorScheme(.light)
}

#Preview(
    "LLM Issue - Quota Exhausted",
    traits: .fixedLayout(width: PreviewFrames.llmIssueCanvas.width, height: PreviewFrames.llmIssueCanvas.height)
) {
    ZStack {
        VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
        LinearGradient(
            colors: [Color.accentColor.opacity(0.08), Color.clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        LLMUserFacingIssueCanvasView(
            issue: LLMUserFacingIssue(
                provider: .openAI,
                operation: .execution,
                kind: .quotaOrBudgetExhausted,
                providerMessage: "You exceeded your current quota, please check your plan and billing details.",
                httpStatus: 429,
                providerCode: "insufficient_quota",
                requestID: "req_preview_quota"
            ),
            onOpenSettings: {},
            onOpenProviderConsole: {}
        )
        .padding(24)
    }
    .preferredColorScheme(.light)
}

#Preview(
    "LLM Issue - Billing or Tier",
    traits: .fixedLayout(width: PreviewFrames.llmIssueCanvas.width, height: PreviewFrames.llmIssueCanvas.height)
) {
    ZStack {
        VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
        LinearGradient(
            colors: [Color.accentColor.opacity(0.08), Color.clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        LLMUserFacingIssueCanvasView(
            issue: LLMUserFacingIssue(
                provider: .gemini,
                operation: .taskExtraction,
                kind: .billingOrTierNotEnabled,
                providerMessage: "FAILED_PRECONDITION: Billing account not configured for requested model tier.",
                httpStatus: 400,
                providerCode: "FAILED_PRECONDITION",
                requestID: nil
            ),
            onOpenSettings: {},
            onOpenProviderConsole: {}
        )
        .padding(24)
    }
    .preferredColorScheme(.light)
}

#Preview(
    "Recording Preflight Dialog",
    traits: .fixedLayout(width: PreviewFrames.recordingDialog.width, height: PreviewFrames.recordingDialog.height)
) {
    RecordingPreflightDialogCanvasView(
        state: RecordingPreflightDialogState(
            missingRequirements: [.geminiAPIKey, .screenRecording, .microphone, .inputMonitoring]
        ),
        apiKeyStatusMessage: nil,
        apiKeyErrorMessage: nil,
        onDismiss: {},
        onOpenSettingsForRequirement: { _ in },
        onSaveGeminiKey: { _ in },
        onContinue: {}
    )
    .preferredColorScheme(.light)
}

#Preview(
    "Run Task Preflight Dialog",
    traits: .fixedLayout(width: PreviewFrames.recordingDialog.width, height: PreviewFrames.recordingDialog.height)
) {
    RunTaskPreflightDialogCanvasView(
        state: RunTaskPreflightDialogState(
            missingRequirements: [.openAIAPIKey, .accessibility]
        ),
        apiKeyStatusMessage: nil,
        apiKeyErrorMessage: nil,
        onDismiss: {},
        onOpenSettingsForRequirement: { _ in },
        onSaveOpenAIKey: { _ in },
        onContinue: {}
    )
    .preferredColorScheme(.light)
}

#Preview(
    "Task Detail - Created Task (Default)",
    traits: .fixedLayout(width: PreviewFrames.default.width, height: PreviewFrames.default.height)
) {
    PreviewMainShellView(store: PreviewMainShellFactory.taskDetailStore())
}

#endif
