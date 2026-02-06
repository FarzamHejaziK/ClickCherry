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
                OnboardingFlowView(onboardingStateStore: onboardingStateStore)
            case .mainShell:
                MainShellView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
    }
}

private struct OnboardingFlowView: View {
    @Bindable var onboardingStateStore: OnboardingStateStore

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("First-Run Setup")
                    .font(.title)
                    .fontWeight(.semibold)
                Text("Step \(onboardingStateStore.currentStep.rawValue + 1) of \(OnboardingStep.allCases.count): \(onboardingStateStore.currentStep.title)")
                    .foregroundStyle(.secondary)
            }

            Group {
                switch onboardingStateStore.currentStep {
                case .welcome:
                    WelcomeStepView()
                case .providerSetup:
                    ProviderSetupStepView(onboardingStateStore: onboardingStateStore)
                case .permissionsPreflight:
                    PermissionsStepView(onboardingStateStore: onboardingStateStore)
                case .ready:
                    ReadyStepView(onboardingStateStore: onboardingStateStore)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Button("Back") {
                    onboardingStateStore.goBack()
                }
                .disabled(!onboardingStateStore.canGoBack)

                Spacer()

                if onboardingStateStore.currentStep == .ready {
                    Button("Finish Setup") {
                        onboardingStateStore.completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Continue") {
                        onboardingStateStore.goForward()
                    }
                    .disabled(!onboardingStateStore.canContinueCurrentStep)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

private struct WelcomeStepView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Welcome to Task Agent")
                .font(.title2)
                .fontWeight(.semibold)
            Text("This setup will configure model providers and required macOS permissions before task creation.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct ProviderSetupStepView: View {
    @Bindable var onboardingStateStore: OnboardingStateStore
    @State private var openAIKeyInput = ""
    @State private var anthropicKeyInput = ""
    @State private var geminiKeyInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Provider Setup")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Required in v1: OpenAI or Anthropic, and Gemini.")
                .foregroundStyle(.secondary)

            providerInputSection(
                title: "OpenAI API Key",
                saved: onboardingStateStore.providerSetupState.hasOpenAIKey,
                keyInput: $openAIKeyInput,
                onSave: {
                    if onboardingStateStore.saveProviderKey(openAIKeyInput, for: .openAI) {
                        openAIKeyInput = ""
                    }
                },
                onRemove: {
                    onboardingStateStore.clearProviderKey(for: .openAI)
                }
            )
            providerInputSection(
                title: "Anthropic API Key",
                saved: onboardingStateStore.providerSetupState.hasAnthropicKey,
                keyInput: $anthropicKeyInput,
                onSave: {
                    if onboardingStateStore.saveProviderKey(anthropicKeyInput, for: .anthropic) {
                        anthropicKeyInput = ""
                    }
                },
                onRemove: {
                    onboardingStateStore.clearProviderKey(for: .anthropic)
                }
            )
            providerInputSection(
                title: "Gemini API Key",
                saved: onboardingStateStore.providerSetupState.hasGeminiKey,
                keyInput: $geminiKeyInput,
                onSave: {
                    if onboardingStateStore.saveProviderKey(geminiKeyInput, for: .gemini) {
                        geminiKeyInput = ""
                    }
                },
                onRemove: {
                    onboardingStateStore.clearProviderKey(for: .gemini)
                }
            )

            if let persistenceErrorMessage = onboardingStateStore.persistenceErrorMessage {
                Text(persistenceErrorMessage)
                    .foregroundStyle(.red)
            }

            if !onboardingStateStore.providerSetupState.isReadyForOnboardingCompletion {
                Text("Continue is disabled until one core provider (OpenAI/Anthropic) and Gemini are configured.")
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func providerInputSection(
        title: String,
        saved: Bool,
        keyInput: Binding<String>,
        onSave: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .fontWeight(.medium)
                Spacer()
                Text(saved ? "Saved" : "Not Saved")
                    .foregroundStyle(saved ? .green : .secondary)
            }

            SecureField("Enter key", text: keyInput)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Save Key", action: onSave)
                    .buttonStyle(.borderedProminent)
                Button("Remove Saved Key", action: onRemove)
                    .buttonStyle(.bordered)
                    .disabled(!saved)
            }
        }
    }
}

private struct PermissionsStepView: View {
    @Bindable var onboardingStateStore: OnboardingStateStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Permissions Preflight")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Open System Settings, grant each permission, then confirm status in-app.")
                .foregroundStyle(.secondary)

            permissionRow(
                title: "Screen Recording",
                status: onboardingStateStore.screenRecordingStatus,
                onOpenSettings: {
                    onboardingStateStore.openPermissionSettings(for: .screenRecording)
                },
                onCheckStatus: {
                    onboardingStateStore.refreshPermissionStatus(for: .screenRecording)
                }
            )
            permissionRow(
                title: "Accessibility",
                status: onboardingStateStore.accessibilityStatus,
                onOpenSettings: {
                    onboardingStateStore.openPermissionSettings(for: .accessibility)
                },
                onCheckStatus: {
                    onboardingStateStore.refreshPermissionStatus(for: .accessibility)
                }
            )
            VStack(alignment: .leading, spacing: 8) {
                permissionRow(
                    title: "Automation",
                    status: onboardingStateStore.automationStatus,
                    onOpenSettings: {
                        onboardingStateStore.openPermissionSettings(for: .automation)
                    },
                    onCheckStatus: {
                        onboardingStateStore.refreshPermissionStatus(for: .automation)
                    }
                )

                Text("Automation status may require manual confirmation after granting in System Settings.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)

                HStack {
                    Button("Mark Granted") {
                        onboardingStateStore.confirmAutomationPermission(granted: true)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Mark Not Granted") {
                        onboardingStateStore.confirmAutomationPermission(granted: false)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if !onboardingStateStore.areRequiredPermissionsGranted {
                Text("Continue is disabled until all required permissions are granted.")
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        status: PermissionGrantStatus,
        onOpenSettings: @escaping () -> Void,
        onCheckStatus: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .fontWeight(.medium)
                Spacer()
                Text(status.label)
                    .foregroundStyle(status == .granted ? .green : (status == .notGranted ? .orange : .secondary))
            }

            HStack {
                Button("Open Settings", action: onOpenSettings)
                    .buttonStyle(.bordered)
                Button("Check Status", action: onCheckStatus)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct ReadyStepView: View {
    @Bindable var onboardingStateStore: OnboardingStateStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ready to Start")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Provider setup and permission preflight are complete.")
                .foregroundStyle(.secondary)
            Text("Click Finish Setup to enter the main workspace.")
                .foregroundStyle(.secondary)

            LabeledContent("Core provider ready", value: onboardingStateStore.providerSetupState.hasCoreProvider ? "Yes" : "No")
            LabeledContent("Gemini ready", value: onboardingStateStore.providerSetupState.hasGeminiKey ? "Yes" : "No")
            LabeledContent("Permissions ready", value: onboardingStateStore.areRequiredPermissionsGranted ? "Yes" : "No")
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
