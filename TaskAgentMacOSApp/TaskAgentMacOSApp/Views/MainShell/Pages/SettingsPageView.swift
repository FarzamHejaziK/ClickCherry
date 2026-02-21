import AppKit
import SwiftUI

struct MainShellSettingsView: View {
    enum Section: Equatable {
        case modelSetup
        case permissions
    }

    @Bindable var mainShellStateStore: MainShellStateStore

    @State private var selectedSection: Section = .modelSetup

    @State private var openAIKeyInput = ""
    @State private var geminiKeyInput = ""
    @State private var isOpenAIKeyVisible = false
    @State private var isGeminiKeyVisible = false

    @State private var permissionStatuses = PermissionStatuses()
    @State private var enableTemporaryFullReset = false

    var body: some View {
        HSplitView {
            settingsSidebar
                .frame(minWidth: 240, idealWidth: 260, maxWidth: 320, maxHeight: .infinity)

            settingsDetail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: selectedSection) {
            switch selectedSection {
            case .modelSetup:
                // Ensure the Saved/Not Saved pills reflect the current Keychain state when entering this page.
                mainShellStateStore.refreshProviderKeysState()
            case .permissions:
                while !Task.isCancelled {
                    refreshPermissionStatuses()
                    try? await Task.sleep(nanoseconds: 750_000_000)
                }
            }
        }
        .onAppear {
            mainShellStateStore.refreshProviderKeysState()
            refreshPermissionStatuses()
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                mainShellStateStore.closeSettings()
            } label: {
                HStack(spacing: 10) {
                    Image("BackIcon")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(.secondary)

                    Text("Back")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            Divider()
                .opacity(0.35)
                .padding(.vertical, 6)

            Text("Settings")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)

            SettingsMenuRow(
                iconAssetName: "ModelsIcon",
                title: "Model Setup",
                isSelected: selectedSection == .modelSetup,
                action: { selectedSection = .modelSetup }
            )

            SettingsMenuRow(
                iconAssetName: "PermissionsIcon",
                title: "Permissions",
                isSelected: selectedSection == .permissions,
                action: { selectedSection = .permissions }
            )

            Spacer(minLength: 0)
        }
        .padding(12)
        .background {
            ZStack {
                VisualEffectView(material: .sidebar, blendingMode: .withinWindow)

                // Match the main-shell sidebar style (accent-tinted material).
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.16),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.10),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
    }

    private var settingsDetail: some View {
        ScrollView {
            VStack(spacing: 18) {
                switch selectedSection {
                case .modelSetup:
                    modelSetupSection
                case .permissions:
                    permissionsSection
                }

                Spacer(minLength: 12)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
        .scrollIndicators(.automatic)
    }

    private var modelSetupSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Model Setup")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Configure provider API keys. Keys are stored securely in macOS Keychain.")
                    .foregroundStyle(.secondary)
            }

            ProviderKeyEntryPanelView(
                title1: "OpenAI",
                iconAssetName1: "OpenAILogo",
                keyInput1: $openAIKeyInput,
                isKeyVisible1: $isOpenAIKeyVisible,
                saved1: mainShellStateStore.providerSetupState.hasOpenAIKey,
                onSave1: {
                    if mainShellStateStore.saveProviderKey(openAIKeyInput, for: .openAI) {
                        openAIKeyInput = ""
                    }
                },
                title2: "Gemini",
                iconAssetName2: "GeminiLogo",
                keyInput2: $geminiKeyInput,
                isKeyVisible2: $isGeminiKeyVisible,
                saved2: mainShellStateStore.providerSetupState.hasGeminiKey,
                onSave2: {
                    if mainShellStateStore.saveProviderKey(geminiKeyInput, for: .gemini) {
                        geminiKeyInput = ""
                    }
                }
            )

            if let apiKeyStatusMessage = mainShellStateStore.apiKeyStatusMessage {
                Text(apiKeyStatusMessage)
                    .foregroundStyle(.green)
            }

            if let apiKeyErrorMessage = mainShellStateStore.apiKeyErrorMessage {
                Text(apiKeyErrorMessage)
                    .foregroundStyle(.red)
            }

            Divider()
                .padding(.top, 4)
                .opacity(0.4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Start Over")
                    .font(.headline)

                Text("Show onboarding again and restart setup flow from the welcome step.")
                    .foregroundStyle(.secondary)

                Button("Start Over (Show Onboarding)") {
                    mainShellStateStore.resetOnboardingAndReturnToSetup()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }

            Divider()
                .padding(.top, 4)
                .opacity(0.4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Temporary Reset Toggle")
                    .font(.headline)

                Text("Temporary developer utility: clear saved OpenAI/Gemini keys, reset onboarding, and attempt a macOS permission reset (with app relaunch on success). If macOS does not allow automatic reset, revoke permissions manually in System Settings.")
                    .foregroundStyle(.secondary)

                Toggle("Enable temporary full reset", isOn: $enableTemporaryFullReset)
                    .toggleStyle(.switch)

                Button("Run Temporary Reset (Clear Keys + Onboarding)") {
                    mainShellStateStore.resetSetupAndReturnToOnboarding()
                    enableTemporaryFullReset = false
                    openAIKeyInput = ""
                    geminiKeyInput = ""
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!enableTemporaryFullReset)
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Permissions")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Use Open Settings to grant permissions. Status updates automatically.")
                    .foregroundStyle(.secondary)

                Text("For reliable registration in Privacy lists, run ClickCherry from /Applications.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }

            VStack(spacing: 0) {
                PermissionRowView(
                    title: "Screen Recording",
                    status: permissionStatuses.screenRecording,
                    onOpenSettings: {
                        mainShellStateStore.openPermissionSettings(for: .screenRecording)
                    }
                )

                permissionDivider

                PermissionRowView(
                    title: "Microphone (Voice)",
                    status: permissionStatuses.microphone,
                    footnote: "Needed to record your voice during screen recordings.",
                    onOpenSettings: {
                        mainShellStateStore.openPermissionSettings(for: .microphone)
                    }
                )

                permissionDivider

                PermissionRowView(
                    title: "Accessibility",
                    status: permissionStatuses.accessibility,
                    onOpenSettings: {
                        mainShellStateStore.openPermissionSettings(for: .accessibility)
                    }
                )

                permissionDivider

                PermissionRowView(
                    title: "Input Monitoring",
                    status: permissionStatuses.inputMonitoring,
                    footnote: "Needed to stop the agent with Escape.",
                    onOpenSettings: {
                        mainShellStateStore.openPermissionSettings(for: .inputMonitoring)
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
        }
        .frame(maxWidth: 640, alignment: .leading)
    }

    private var permissionDivider: some View {
        Divider()
            .opacity(0.35)
            .padding(.leading, PermissionRowMetrics.rowPaddingX)
    }

    private func refreshPermissionStatuses() {
        permissionStatuses = PermissionStatuses(
            screenRecording: mainShellStateStore.permissionStatus(for: .screenRecording),
            microphone: mainShellStateStore.permissionStatus(for: .microphone),
            accessibility: mainShellStateStore.permissionStatus(for: .accessibility),
            inputMonitoring: mainShellStateStore.permissionStatus(for: .inputMonitoring)
        )
    }
}

private struct PermissionStatuses: Equatable {
    var screenRecording: PermissionGrantStatus = .unknown
    var microphone: PermissionGrantStatus = .unknown
    var accessibility: PermissionGrantStatus = .unknown
    var inputMonitoring: PermissionGrantStatus = .unknown
}

private struct SettingsMenuRow: View {
    let iconAssetName: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(iconAssetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)

                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.22)
        }
        if isHovered {
            return Color.primary.opacity(0.06)
        }
        return Color.clear
    }
}
