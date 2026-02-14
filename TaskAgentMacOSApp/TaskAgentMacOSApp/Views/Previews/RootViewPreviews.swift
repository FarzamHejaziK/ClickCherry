import SwiftUI

#if DEBUG

#Preview("RootView") {
    RootView()
        .frame(width: 1100, height: 720)
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
        providerSetupState: ProviderSetupState = ProviderSetupState(hasOpenAIKey: false, hasAnthropicKey: false, hasGeminiKey: false),
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

#Preview("Startup - Welcome") {
    RootView(onboardingStateStore: PreviewOnboardingFactory.store(currentStep: .welcome, hasCompletedOnboarding: false))
        .frame(width: 1100, height: 720)
}

#Preview("Startup - Provider Setup") {
    RootView(onboardingStateStore: PreviewOnboardingFactory.store(currentStep: .providerSetup, hasCompletedOnboarding: false))
        .frame(width: 1100, height: 720)
}

#Preview("Startup - Permissions") {
    RootView(onboardingStateStore: PreviewOnboardingFactory.store(currentStep: .permissionsPreflight, hasCompletedOnboarding: false))
        .frame(width: 1100, height: 720)
}

#Preview("Startup - Ready") {
    RootView(onboardingStateStore: PreviewOnboardingFactory.store(
        currentStep: .ready,
        hasCompletedOnboarding: false,
        providerSetupState: ProviderSetupState(hasOpenAIKey: true, hasAnthropicKey: false, hasGeminiKey: true),
        permissionStatuses: PreviewPermissionStatuses(
            screenRecording: .granted,
            microphone: .granted,
            accessibility: .granted,
            inputMonitoring: .granted
        )
    ))
    .frame(width: 1100, height: 720)
}

#Preview("New Task") {
    let store = MainShellStateStore()
    store.openNewTask()
    return MainShellView(mainShellStateStore: store)
        .frame(width: 1100, height: 720)
}

#Preview("Settings") {
    let store = MainShellStateStore()
    store.openSettings()
    return MainShellView(mainShellStateStore: store)
        .frame(width: 1100, height: 720)
}

#Preview("Recording Finished Dialog") {
    let recording = RecordingRecord(
        id: UUID().uuidString,
        fileName: "ClickCherry-Recording-Example.mov",
        addedAt: Date(),
        fileURL: URL(fileURLWithPath: "/tmp/clickcherry-preview-example.mov"),
        fileSizeBytes: 123_456_789
    )
    return RecordingFinishedDialogView(
        recording: recording,
        onRecordAgain: {},
        onExtractTask: {}
    )
    .frame(width: 780, height: 560)
}

#endif
