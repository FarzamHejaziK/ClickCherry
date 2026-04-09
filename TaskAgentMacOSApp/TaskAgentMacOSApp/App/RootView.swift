import SwiftUI
import Combine

struct RootView: View {
    @State private var onboardingStateStore: OnboardingStateStore

    init(onboardingStateStore: OnboardingStateStore = OnboardingStateStore()) {
        _onboardingStateStore = State(initialValue: onboardingStateStore)
    }

    var body: some View {
        let isOnboarding = onboardingStateStore.route == .onboarding
        Group {
            switch onboardingStateStore.route {
            case .onboarding:
                OnboardingFlowView(onboardingStateStore: onboardingStateStore)
            case .mainShell:
                MainShellView()
            }
        }
        .background(WindowTitlebarBrandInstaller())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isOnboarding ? .center : .topLeading)
        .onReceive(NotificationCenter.default.publisher(for: .clickCherryResetOnboardingRequested)) { _ in
            onboardingStateStore = OnboardingStateStore(
                currentStep: .welcome,
                hasCompletedOnboarding: false
            )
        }
        // The onboarding flow manages its own padding; the main shell is edge-to-edge.
        .padding(0)
    }
}
