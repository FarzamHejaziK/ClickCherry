import SwiftUI

struct PermissionsStepView: View {
    @Bindable var onboardingStateStore: OnboardingStateStore

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 10) {
                Text("Permissions Preflight")
                    .font(.system(size: 24, weight: .semibold))
                Text("Use Open Settings to grant permissions. Status updates automatically.")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            ScrollView {
                VStack(spacing: 14) {
                    PermissionsPanelView(onboardingStateStore: onboardingStateStore)
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 4)
            }
            .frame(maxHeight: 360)
            .scrollIndicators(.never)

            if !onboardingStateStore.areRequiredPermissionsGranted {
                Text("Continue is disabled until all required permissions are granted. You can also Skip and grant them later.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
            }
        }
        .task {
            while !Task.isCancelled {
                onboardingStateStore.pollPermissionStatuses()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}

private struct PermissionsPanelView: View {
    @Bindable var onboardingStateStore: OnboardingStateStore

    var body: some View {
        VStack(spacing: 0) {
            PermissionRowView(
                title: "Screen Recording",
                status: onboardingStateStore.screenRecordingStatus,
                onOpenSettings: {
                    onboardingStateStore.refreshPermissionStatus(for: .screenRecording)
                    onboardingStateStore.openPermissionSettings(for: .screenRecording)
                }
            )

            permissionDivider

            PermissionRowView(
                title: "Microphone (Voice)",
                status: onboardingStateStore.microphoneStatus,
                footnote: "Needed to record your voice during screen recordings.",
                onOpenSettings: {
                    onboardingStateStore.refreshPermissionStatus(for: .microphone)
                    onboardingStateStore.openPermissionSettings(for: .microphone)
                }
            )

            permissionDivider

            PermissionRowView(
                title: "Accessibility",
                status: onboardingStateStore.accessibilityStatus,
                onOpenSettings: {
                    onboardingStateStore.refreshPermissionStatus(for: .accessibility)
                    onboardingStateStore.openPermissionSettings(for: .accessibility)
                }
            )

            permissionDivider

            PermissionRowView(
                title: "Input Monitoring",
                status: onboardingStateStore.inputMonitoringStatus,
                footnote: "Needed to stop the agent with Escape.",
                onOpenSettings: {
                    onboardingStateStore.refreshPermissionStatus(for: .inputMonitoring)
                    onboardingStateStore.openPermissionSettings(for: .inputMonitoring)
                }
            )
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14))
        }
        .shadow(color: Color.black.opacity(0.22), radius: 26, x: 0, y: 16)
        .frame(maxWidth: 720)
    }

    private var permissionDivider: some View {
        Divider()
            .opacity(0.35)
            .padding(.leading, PermissionRowMetrics.rowPaddingX)
    }
}
