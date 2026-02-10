import Testing
import Security
@testable import TaskAgentMacOSApp

private final class EmptyAPIKeyStore: APIKeyStore {
    func hasKey(for provider: ProviderIdentifier) -> Bool { false }
    func readKey(for provider: ProviderIdentifier) throws -> String? { nil }
    func setKey(_ key: String?, for provider: ProviderIdentifier) throws {
        if key == "__fail__" {
            throw KeychainStoreError.unhandledStatus(errSecParam)
        }
    }
}

private final class StaticCompletionStore: OnboardingCompletionStore {
    var hasCompletedOnboarding: Bool

    init(hasCompletedOnboarding: Bool = false) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
}

private final class StatusOnlyPermissionService: PermissionService {
    var statuses: [AppPermission: PermissionGrantStatus]

    init(statuses: [AppPermission: PermissionGrantStatus] = [:]) {
        self.statuses = statuses
    }

    func openSystemSettings(for permission: AppPermission) {}

    func currentStatus(for permission: AppPermission) -> PermissionGrantStatus {
        statuses[permission] ?? .unknown
    }
}

struct OnboardingStateStoreTests {
    private func makeStore(
        currentStep: OnboardingStep = .welcome,
        hasScreenRecordingPermission: Bool = false,
        hasAccessibilityPermission: Bool = false,
        hasInputMonitoringPermission: Bool = false,
        hasAutomationPermission: Bool = false,
        hasCompletedOnboarding: Bool = false,
        permissionService: PermissionService = StatusOnlyPermissionService()
    ) -> OnboardingStateStore {
        OnboardingStateStore(
            keyStore: EmptyAPIKeyStore(),
            completionStore: StaticCompletionStore(hasCompletedOnboarding: hasCompletedOnboarding),
            permissionService: permissionService,
            currentStep: currentStep,
            hasScreenRecordingPermission: hasScreenRecordingPermission,
            hasAccessibilityPermission: hasAccessibilityPermission,
            hasInputMonitoringPermission: hasInputMonitoringPermission,
            hasAutomationPermission: hasAutomationPermission,
            hasCompletedOnboarding: hasCompletedOnboarding
        )
    }

    @Test
    func defaultsToOnboardingRoute() {
        let store = makeStore()
        #expect(store.route == .onboarding)
    }

    @Test
    func onlyRoutesToMainShellAfterOnboardingCompletion() {
        let store = makeStore(hasCompletedOnboarding: true)
        #expect(store.route == .mainShell)
    }

    @Test
    func providerStepBlocksForwardUntilRequiredProvidersConfigured() {
        let store = makeStore(currentStep: .providerSetup)
        #expect(!store.canContinueCurrentStep)

        store.goForward()
        #expect(store.currentStep == .providerSetup)

        store.providerSetupState = ProviderSetupState(
            hasOpenAIKey: true,
            hasAnthropicKey: false,
            hasGeminiKey: true
        )

        #expect(store.canContinueCurrentStep)
        store.goForward()
        #expect(store.currentStep == .permissionsPreflight)
    }

    @Test
    func permissionStepBlocksForwardUntilAllPermissionsGranted() {
        let store = makeStore(
            currentStep: .permissionsPreflight,
            hasScreenRecordingPermission: true,
            hasAccessibilityPermission: false,
            hasInputMonitoringPermission: true,
            hasAutomationPermission: true
        )
        #expect(!store.canContinueCurrentStep)

        store.goForward()
        #expect(store.currentStep == .permissionsPreflight)

        store.accessibilityStatus = .granted
        #expect(store.canContinueCurrentStep)

        store.goForward()
        #expect(store.currentStep == .ready)
    }

    @Test
    func refreshPermissionStatusUpdatesScreenAndAccessibility() {
        let permissionService = StatusOnlyPermissionService(
            statuses: [
                .screenRecording: .granted,
                .accessibility: .granted,
                .inputMonitoring: .granted
            ]
        )

        let store = makeStore(
            hasAutomationPermission: true,
            permissionService: permissionService
        )

        store.refreshPermissionStatus(for: .screenRecording)
        store.refreshPermissionStatus(for: .accessibility)
        store.refreshPermissionStatus(for: .inputMonitoring)

        #expect(store.screenRecordingStatus == .granted)
        #expect(store.accessibilityStatus == .granted)
        #expect(store.areRequiredPermissionsGranted)
    }

    @Test
    func automationPermissionRequiresManualConfirmationWhenStatusUnknown() {
        let permissionService = StatusOnlyPermissionService(statuses: [.automation: .unknown])
        let store = makeStore(permissionService: permissionService)

        store.refreshPermissionStatus(for: .automation)
        #expect(store.automationStatus == .notGranted)

        store.confirmAutomationPermission(granted: true)
        #expect(store.automationStatus == .granted)
    }

    @Test
    func permissionTestingBypassMarksAllPermissionsGranted() {
        let store = makeStore(
            hasScreenRecordingPermission: false,
            hasAccessibilityPermission: false,
            hasInputMonitoringPermission: false,
            hasAutomationPermission: false
        )
        #expect(!store.areRequiredPermissionsGranted)

        store.enablePermissionTestingBypass()

        #expect(store.screenRecordingStatus == .granted)
        #expect(store.accessibilityStatus == .granted)
        #expect(store.inputMonitoringStatus == .granted)
        #expect(store.automationStatus == .granted)
        #expect(store.areRequiredPermissionsGranted)
    }

    @Test
    func completeOnboardingTransitionsToMainShell() {
        let store = makeStore(currentStep: .ready)
        #expect(store.route == .onboarding)

        store.completeOnboarding()
        #expect(store.route == .mainShell)
    }
}
