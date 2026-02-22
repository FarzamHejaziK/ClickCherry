import SwiftUI

struct ReadyStepView: View {
    @Bindable var onboardingStateStore: OnboardingStateStore

    private let highlightColor = Color.accentColor

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 12) {
                Text("Ready to Start")
                    .font(.system(size: 24, weight: .semibold))
                Text("Finish setup now. You can grant missing keys and permissions later.")
                    .foregroundStyle(.secondary)
                Text("Click Finish Setup to enter the main workspace.")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background {
                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                ZStack {
                    shape.fill(.thinMaterial)
                    shape.fill(
                        LinearGradient(
                            colors: [
                                highlightColor.opacity(0.15),
                                highlightColor.opacity(0.06),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(highlightColor.opacity(0.24), lineWidth: 1)
            }

            OnboardingHeroView(size: .large)
                .padding(.top, 4)
                .padding(.bottom, 2)

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
            .frame(maxWidth: 380, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(
                        LinearGradient(
                            colors: [
                                highlightColor.opacity(0.12),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private func readinessRow(title: String, isReady: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isReady ? .green : .orange)
            Text(title)
                .font(.system(size: 19, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill((isReady ? Color.green : Color.orange).opacity(0.11))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder((isReady ? Color.green : Color.orange).opacity(0.28), lineWidth: 1)
        }
    }
}
