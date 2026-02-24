import SwiftUI

struct ReadyStepView: View {
    @Bindable var onboardingStateStore: OnboardingStateStore

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 10) {
                Text("Ready to Start")
                    .font(.system(size: 24, weight: .semibold))
                Text("Finish setup now. You can grant missing keys and permissions later.")
                    .foregroundStyle(.secondary)
                Text("Click Finish Setup to enter the main workspace.")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            OnboardingHeroView(size: .large)

            VStack(alignment: .leading, spacing: 10) {
                readinessRow(
                    title: "Core provider ready",
                    isReady: onboardingStateStore.providerSetupState.hasCoreProvider
                )
                readinessRow(
                    title: "Model ready",
                    isReady: onboardingStateStore.providerSetupState.hasGeminiKey
                )
                readinessRow(
                    title: "Permissions ready",
                    isReady: onboardingStateStore.areRequiredPermissionsGranted
                )
            }
            .frame(maxWidth: 340, alignment: .leading)
        }
    }

    @ViewBuilder
    private func readinessRow(title: String, isReady: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isReady ? .green : .orange)
            Text(title)
            Spacer()
        }
        .font(.headline)
    }
}
