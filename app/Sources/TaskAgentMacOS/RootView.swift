import SwiftUI

struct RootView: View {
    @State private var onboardingStateStore: OnboardingStateStore

    init(onboardingStateStore: OnboardingStateStore = OnboardingStateStore()) {
        _onboardingStateStore = State(initialValue: onboardingStateStore)
    }

    var body: some View {
        Group {
            switch onboardingStateStore.route {
            case .onboarding:
                OnboardingGateView()
            case .mainShell:
                MainShellView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
    }
}

private struct OnboardingGateView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Welcome to Task Agent")
                .font(.title)
                .fontWeight(.semibold)
            Text("Complete provider setup to continue.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct MainShellView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Task Agent macOS")
                .font(.title)
                .fontWeight(.semibold)
            Text("Main task workspace shell.")
                .foregroundStyle(.secondary)
        }
    }
}
