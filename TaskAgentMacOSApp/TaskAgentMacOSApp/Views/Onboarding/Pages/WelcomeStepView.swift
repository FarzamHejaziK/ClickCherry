import SwiftUI

struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 10) {
                Text("Welcome to ClickCherry")
                    .font(.system(size: 24, weight: .semibold))
                Text("This setup will configure model providers and required macOS permissions before task creation.")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            OnboardingHeroView(size: .large)
        }
    }
}

