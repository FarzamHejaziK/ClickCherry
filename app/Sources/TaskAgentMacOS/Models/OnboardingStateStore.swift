import Foundation
import Observation

enum AppRoute: Equatable {
    case onboarding
    case mainShell
}

enum OnboardingStep: Int, CaseIterable, Equatable {
    case welcome
    case providerSetup
    case permissionsPreflight
    case ready

    var title: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .providerSetup:
            return "Provider Setup"
        case .permissionsPreflight:
            return "Permissions"
        case .ready:
            return "Ready"
        }
    }
}

@Observable
final class OnboardingStateStore {
    private let keyStore: any APIKeyStore
    private var completionStore: any OnboardingCompletionStore
    private let permissionService: any PermissionService

    var currentStep: OnboardingStep
    var providerSetupState: ProviderSetupState
    var screenRecordingStatus: PermissionGrantStatus
    var accessibilityStatus: PermissionGrantStatus
    var automationStatus: PermissionGrantStatus
    var hasCompletedOnboarding: Bool
    var persistenceErrorMessage: String?

    init(
        keyStore: any APIKeyStore = KeychainAPIKeyStore(),
        completionStore: any OnboardingCompletionStore = UserDefaultsOnboardingCompletionStore(),
        permissionService: any PermissionService = MacPermissionService(),
        currentStep: OnboardingStep = .welcome,
        providerSetupState: ProviderSetupState? = nil,
        hasScreenRecordingPermission: Bool = false,
        hasAccessibilityPermission: Bool = false,
        hasAutomationPermission: Bool = false,
        hasCompletedOnboarding: Bool? = nil
    ) {
        self.keyStore = keyStore
        self.completionStore = completionStore
        self.permissionService = permissionService
        self.currentStep = currentStep
        self.providerSetupState = providerSetupState ?? Self.loadProviderSetupState(from: keyStore)
        self.screenRecordingStatus = hasScreenRecordingPermission ? .granted : .notGranted
        self.accessibilityStatus = hasAccessibilityPermission ? .granted : .notGranted
        self.automationStatus = hasAutomationPermission ? .granted : .notGranted
        self.hasCompletedOnboarding = hasCompletedOnboarding ?? completionStore.hasCompletedOnboarding
        self.persistenceErrorMessage = nil
    }

    var route: AppRoute {
        if hasCompletedOnboarding {
            return .mainShell
        }

        return .onboarding
    }

    var areRequiredPermissionsGranted: Bool {
        screenRecordingStatus == .granted
            && accessibilityStatus == .granted
            && automationStatus == .granted
    }

    var canContinueCurrentStep: Bool {
        switch currentStep {
        case .welcome:
            return true
        case .providerSetup:
            return providerSetupState.isReadyForOnboardingCompletion
        case .permissionsPreflight:
            return areRequiredPermissionsGranted
        case .ready:
            return true
        }
    }

    var canGoBack: Bool {
        currentStep != .welcome
    }

    func goBack() {
        guard let previous = OnboardingStep(rawValue: currentStep.rawValue - 1) else {
            return
        }

        currentStep = previous
    }

    func goForward() {
        guard canContinueCurrentStep else {
            return
        }

        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else {
            return
        }

        currentStep = next
    }

    func completeOnboarding() {
        guard currentStep == .ready else {
            return
        }

        hasCompletedOnboarding = true
        completionStore.hasCompletedOnboarding = true
    }

    @discardableResult
    func saveProviderKey(_ rawKey: String, for provider: ProviderIdentifier) -> Bool {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !key.isEmpty else {
            persistenceErrorMessage = "API key cannot be empty."
            return false
        }

        do {
            try keyStore.setKey(key, for: provider)
            updateProviderSetupState(saved: true, for: provider)
            persistenceErrorMessage = nil
            return true
        } catch {
            persistenceErrorMessage = "Failed to save API key."
            return false
        }
    }

    func clearProviderKey(for provider: ProviderIdentifier) {
        do {
            try keyStore.setKey(nil, for: provider)
            updateProviderSetupState(saved: false, for: provider)
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = "Failed to remove saved API key."
        }
    }

    func openPermissionSettings(for permission: AppPermission) {
        permissionService.openSystemSettings(for: permission)
    }

    func refreshPermissionStatus(for permission: AppPermission) {
        let status = permissionService.currentStatus(for: permission)

        switch permission {
        case .screenRecording:
            screenRecordingStatus = status
        case .accessibility:
            accessibilityStatus = status
        case .automation:
            if status != .unknown {
                automationStatus = status
            }
        }
    }

    func confirmAutomationPermission(granted: Bool) {
        automationStatus = granted ? .granted : .notGranted
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

    private static func loadProviderSetupState(from keyStore: any APIKeyStore) -> ProviderSetupState {
        ProviderSetupState(
            hasOpenAIKey: keyStore.hasKey(for: .openAI),
            hasAnthropicKey: keyStore.hasKey(for: .anthropic),
            hasGeminiKey: keyStore.hasKey(for: .gemini)
        )
    }
}
