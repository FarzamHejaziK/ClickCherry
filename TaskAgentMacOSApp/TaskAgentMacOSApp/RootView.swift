import SwiftUI
import UniformTypeIdentifiers

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
            Text("Click Check Status to trigger macOS permission prompts, then use Open Settings to verify grants.")
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

            Divider()
                .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 6) {
                Text("Testing shortcut")
                    .font(.headline)
                Text("Use this only for local development when macOS permission grants are not available.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                Button("Bypass Permissions For Testing") {
                    onboardingStateStore.enablePermissionTestingBypass()
                }
                .buttonStyle(.borderedProminent)
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
    @State private var mainShellStateStore = MainShellStateStore()
    @State private var openAIKeyInput = ""
    @State private var anthropicKeyInput = ""
    @State private var geminiKeyInput = ""
    @State private var isAPIKeySettingsExpanded = false
    @State private var isRecordingImporterPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tasks")
                .font(.title)
                .fontWeight(.semibold)

            DisclosureGroup("Provider API Keys", isExpanded: $isAPIKeySettingsExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Update provider keys any time. Values are stored in macOS Keychain.")
                        .foregroundStyle(.secondary)

                    providerInputSection(
                        title: "OpenAI API Key",
                        saved: mainShellStateStore.providerSetupState.hasOpenAIKey,
                        keyInput: $openAIKeyInput,
                        onSave: {
                            if mainShellStateStore.saveProviderKey(openAIKeyInput, for: .openAI) {
                                openAIKeyInput = ""
                            }
                        },
                        onRemove: {
                            mainShellStateStore.clearProviderKey(for: .openAI)
                        }
                    )

                    providerInputSection(
                        title: "Anthropic API Key",
                        saved: mainShellStateStore.providerSetupState.hasAnthropicKey,
                        keyInput: $anthropicKeyInput,
                        onSave: {
                            if mainShellStateStore.saveProviderKey(anthropicKeyInput, for: .anthropic) {
                                anthropicKeyInput = ""
                            }
                        },
                        onRemove: {
                            mainShellStateStore.clearProviderKey(for: .anthropic)
                        }
                    )

                    providerInputSection(
                        title: "Gemini API Key",
                        saved: mainShellStateStore.providerSetupState.hasGeminiKey,
                        keyInput: $geminiKeyInput,
                        onSave: {
                            if mainShellStateStore.saveProviderKey(geminiKeyInput, for: .gemini) {
                                geminiKeyInput = ""
                            }
                        },
                        onRemove: {
                            mainShellStateStore.clearProviderKey(for: .gemini)
                        }
                    )

                    HStack {
                        Button("Refresh Saved Status") {
                            mainShellStateStore.refreshProviderKeysState()
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }

                    if let apiKeyStatusMessage = mainShellStateStore.apiKeyStatusMessage {
                        Text(apiKeyStatusMessage)
                            .foregroundStyle(.green)
                    }

                    if let apiKeyErrorMessage = mainShellStateStore.apiKeyErrorMessage {
                        Text(apiKeyErrorMessage)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.top, 6)
            }

            HStack(spacing: 10) {
                TextField("New task title", text: $mainShellStateStore.newTaskTitle)
                    .textFieldStyle(.roundedBorder)
                Button("Create Task") {
                    mainShellStateStore.createTask()
                }
                .buttonStyle(.borderedProminent)
            }

            if let errorMessage = mainShellStateStore.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            HStack(alignment: .top, spacing: 20) {
                List(
                    selection: Binding(
                        get: { mainShellStateStore.selectedTaskID },
                        set: { mainShellStateStore.selectTask($0) }
                    )
                ) {
                    ForEach(mainShellStateStore.tasks) { task in
                        Text(task.title)
                            .tag(task.id)
                    }
                }
                .frame(minWidth: 240, maxWidth: 320, minHeight: 320)

                VStack(alignment: .leading, spacing: 10) {
                    if let selectedTask = mainShellStateStore.selectedTask {
                        Text(selectedTask.title)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Task ID: \(selectedTask.id)")
                            .foregroundStyle(.secondary)
                        Text("Workspace: \(selectedTask.workspace.root.path)")
                            .foregroundStyle(.secondary)
                        Text("HEARTBEAT: \(selectedTask.workspace.heartbeatFile.lastPathComponent)")
                            .foregroundStyle(.secondary)

                        Text("HEARTBEAT.md")
                            .font(.headline)
                            .padding(.top, 4)
                        TextEditor(text: $mainShellStateStore.heartbeatMarkdown)
                            .font(.body.monospaced())
                            .frame(minHeight: 220)
                            .border(.quaternary)

                        HStack {
                            Button("Reload") {
                                mainShellStateStore.loadSelectedTaskHeartbeat()
                            }
                            .buttonStyle(.bordered)

                            Button("Save HEARTBEAT") {
                                mainShellStateStore.saveSelectedTaskHeartbeat()
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if let saveStatusMessage = mainShellStateStore.saveStatusMessage {
                            Text(saveStatusMessage)
                                .foregroundStyle(.green)
                        }

                        Divider()
                            .padding(.vertical, 6)

                        HStack {
                            Text("Recordings")
                                .font(.headline)
                            Spacer()
                            Picker("Display", selection: Binding(
                                get: { mainShellStateStore.selectedCaptureDisplayID ?? 1 },
                                set: { mainShellStateStore.selectedCaptureDisplayID = $0 }
                            )) {
                                ForEach(mainShellStateStore.availableCaptureDisplays) { display in
                                    Text(display.label).tag(display.id)
                                }
                            }
                            .frame(width: 140)
                            Picker("Microphone", selection: Binding(
                                get: { mainShellStateStore.selectedCaptureAudioInputID ?? "default" },
                                set: { mainShellStateStore.selectedCaptureAudioInputID = $0 }
                            )) {
                                ForEach(mainShellStateStore.availableCaptureAudioInputs) { input in
                                    Text(input.label).tag(input.id)
                                }
                            }
                            .frame(width: 220)
                            .disabled(mainShellStateStore.isCapturing)
                            Button("Start Capture") {
                                mainShellStateStore.startCapture()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(mainShellStateStore.isCapturing || mainShellStateStore.selectedCaptureDisplayID == nil)
                            Button("Stop Capture") {
                                mainShellStateStore.stopCapture()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!mainShellStateStore.isCapturing)
                            Button("Import .mp4") {
                                isRecordingImporterPresented = true
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if mainShellStateStore.isCapturing {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 10, height: 10)
                                    Text("Recording in progress (\(captureElapsedText(now: context.date))). Red border is shown on the recorded display. Click Stop Capture to finish.")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }

                        if let recordingStatusMessage = mainShellStateStore.recordingStatusMessage {
                            Text(recordingStatusMessage)
                                .foregroundStyle(.green)
                        }

                        if let extractionStatusMessage = mainShellStateStore.extractionStatusMessage {
                            Text(extractionStatusMessage)
                                .foregroundStyle(.green)
                        }

                        if mainShellStateStore.recordings.isEmpty {
                            Text("No recordings imported yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            List(mainShellStateStore.recordings) { recording in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(recording.fileName)
                                            .fontWeight(.medium)
                                        Text(recording.addedAt.formatted(date: .numeric, time: .shortened))
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                    }
                                    Spacer()
                                    Button("Reveal") {
                                        mainShellStateStore.revealRecordingInFinder(recording)
                                    }
                                    .buttonStyle(.borderless)
                                    Button("Play") {
                                        mainShellStateStore.playRecording(recording)
                                    }
                                    .buttonStyle(.borderless)
                                    Button(
                                        mainShellStateStore.isExtractingTask && mainShellStateStore.extractingRecordingID == recording.id
                                            ? "Extracting..."
                                            : "Extract Task"
                                    ) {
                                        Task {
                                            await mainShellStateStore.extractTask(from: recording)
                                        }
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(mainShellStateStore.isExtractingTask)
                                }
                            }
                            .frame(minHeight: 140, maxHeight: 220)
                        }
                    } else {
                        Text("No tasks yet. Create one to begin.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .onAppear {
            mainShellStateStore.reloadTasks()
            mainShellStateStore.refreshProviderKeysState()
            mainShellStateStore.refreshCaptureDisplays()
            mainShellStateStore.refreshCaptureAudioInputs()
        }
        .fileImporter(
            isPresented: $isRecordingImporterPresented,
            allowedContentTypes: [UTType.mpeg4Movie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    return
                }

                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                mainShellStateStore.importRecording(from: url)
            case .failure:
                mainShellStateStore.errorMessage = "File import canceled or failed."
            }
        }
    }

    private func captureElapsedText(now: Date) -> String {
        guard let startedAt = mainShellStateStore.captureStartedAt else {
            return "00:00"
        }
        let interval = Int(now.timeIntervalSince(startedAt))
        let minutes = interval / 60
        let seconds = interval % 60
        return String(format: "%02d:%02d", minutes, seconds)
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
