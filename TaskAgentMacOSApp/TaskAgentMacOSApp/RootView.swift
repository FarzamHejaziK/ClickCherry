import Foundation
import SwiftUI
import UniformTypeIdentifiers
import AppKit

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
                    title: "Input Monitoring",
                    status: onboardingStateStore.inputMonitoringStatus,
                    onOpenSettings: {
                        onboardingStateStore.openPermissionSettings(for: .inputMonitoring)
                    },
                    onCheckStatus: {
                        onboardingStateStore.refreshPermissionStatus(for: .inputMonitoring)
                    }
                )
                Text("Needed so the app can stop an agent run when you use your mouse/keyboard.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
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
    @State private var isDiagnosticsExpanded = false
    @State private var showOnlyLLMFailures = false
    @State private var showOnlyToolUseTrace = false

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

            DisclosureGroup("Diagnostics (LLM + Screenshot)", isExpanded: $isDiagnosticsExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Button(mainShellStateStore.isCapturingDiagnosticScreenshot ? "Capturing..." : "Test Screenshot") {
                            Task {
                                await mainShellStateStore.captureDiagnosticScreenshot()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(mainShellStateStore.isCapturingDiagnosticScreenshot)

                        Button("Clear LLM Log") {
                            mainShellStateStore.clearLLMCallLog()
                        }
                        .buttonStyle(.bordered)

                        Button("Clear LLM Screenshots") {
                            mainShellStateStore.clearLLMScreenshotLog()
                        }
                        .buttonStyle(.bordered)

                        Button("Clear Trace") {
                            mainShellStateStore.clearExecutionTrace()
                        }
                        .buttonStyle(.bordered)

                        Button("Copy All Traces") {
                            mainShellStateStore.copyExecutionTraceToPasteboard(onlyToolUse: showOnlyToolUseTrace)
                        }
                        .buttonStyle(.bordered)

                        Button("Copy LLM Calls") {
                            mainShellStateStore.copyLLMCallLogToPasteboard(onlyFailures: showOnlyLLMFailures)
                        }
                        .buttonStyle(.bordered)

                        Button("Copy All (LLM + Trace)") {
                            mainShellStateStore.copyAllDiagnosticsToPasteboard(
                                onlyToolUseTrace: showOnlyToolUseTrace,
                                onlyLLMFailures: showOnlyLLMFailures
                            )
                        }
                        .buttonStyle(.bordered)

                        Toggle("Only failures", isOn: $showOnlyLLMFailures)
                            .toggleStyle(.switch)

                        Toggle("Only tool_use", isOn: $showOnlyToolUseTrace)
                            .toggleStyle(.switch)

                        Spacer()
                    }

                    Text("Screenshot is captured via `screencapture` and requires Screen Recording permission.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let diagnosticScreenshotStatusMessage = mainShellStateStore.diagnosticScreenshotStatusMessage {
                        Text(diagnosticScreenshotStatusMessage)
                            .foregroundStyle(diagnosticScreenshotStatusMessage.lowercased().contains("failed") ? .red : .green)
                            .font(.caption)
                    }

                    Divider()
                        .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("LLM Screenshots (exact images sent to model)")
                            .font(.headline)

                        let entries = Array(mainShellStateStore.llmScreenshotLog.suffix(24).reversed())
                        if entries.isEmpty {
                            Text("No LLM screenshots captured yet.")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 12) {
                                    ForEach(entries) { entry in
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(spacing: 8) {
                                                Text(entry.source.rawValue.replacingOccurrences(of: "_", with: " "))
                                                    .font(.caption2)
                                                    .fontWeight(.semibold)
                                                    .foregroundStyle(.secondary)

                                                Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)

                                                Spacer()
                                            }

                                            Text("\(entry.mediaType), sent=\(entry.width)x\(entry.height), raw=\(entry.rawByteCount) bytes, base64=\(entry.base64ByteCount) bytes")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)

                                            if let nsImage = NSImage(data: entry.imageData) {
                                                Image(nsImage: nsImage)
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(maxHeight: 180)
                                                    .border(.quaternary)
                                            } else {
                                                Text("Failed to decode image bytes.")
                                                    .font(.caption2)
                                                    .foregroundStyle(.red)
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 420)
                            .border(.quaternary)
                        }
                    }

                    if let data = mainShellStateStore.lastDiagnosticScreenshotPNGData,
                       let nsImage = NSImage(data: data) {
                        VStack(alignment: .leading, spacing: 6) {
                            if let w = mainShellStateStore.lastDiagnosticScreenshotWidth,
                               let h = mainShellStateStore.lastDiagnosticScreenshotHeight {
                                Text("Last screenshot: \(w)x\(h) (\(data.count) bytes)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 220)
                                .border(.quaternary)
                        }
                    }

                    Divider()
                        .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Execution Trace (most recent first)")
                            .font(.headline)

                        let entries = mainShellStateStore.executionTrace
                        let filteredEntries = showOnlyToolUseTrace ? entries.filter { $0.kind == .toolUse } : entries
                        let recentEntries = Array(filteredEntries.suffix(60).reversed())

                        if recentEntries.isEmpty {
                            Text("No execution trace recorded yet.")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 8) {
                                    ForEach(recentEntries) { entry in
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 8) {
                                                Text(entry.kind.rawValue.uppercased())
                                                    .font(.caption2)
                                                    .fontWeight(.semibold)
                                                    .foregroundStyle(color(for: entry.kind))

                                                Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)

                                                Spacer()
                                            }

                                            Text(entry.message)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(8)
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }
                            .frame(maxHeight: 220)
                            .border(.quaternary)
                            .textSelection(.enabled)
                        }

                        if let diagnosticTraceStatusMessage = mainShellStateStore.diagnosticTraceStatusMessage {
                            Text(diagnosticTraceStatusMessage)
                                .foregroundStyle(diagnosticTraceStatusMessage.lowercased().contains("no trace") ? Color.secondary : Color.green)
                                .font(.caption)
                        }
                    }

                    Divider()
                        .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("LLM Calls (most recent first)")
                            .font(.headline)

                        let entries = mainShellStateStore.llmCallLog
                        let filteredEntries = showOnlyLLMFailures ? entries.filter { $0.outcome == .failure } : entries
                        let recentEntries = Array(filteredEntries.suffix(30).reversed())

                        if recentEntries.isEmpty {
                            Text("No LLM calls recorded yet.")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 8) {
                                    ForEach(recentEntries) { entry in
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 8) {
                                                Text(entry.outcome == .success ? "OK" : "FAIL")
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                    .foregroundStyle(entry.outcome == .success ? .green : .red)

                                                Text("\(entry.provider.rawValue)/\(entry.operation.rawValue) #\(entry.attempt)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)

                                                if let status = entry.httpStatus {
                                                    Text("HTTP \(status)")
                                                        .font(.caption)
                                                        .foregroundStyle(status >= 200 && status < 300 ? .green : .red)
                                                }

                                                Text("\(entry.durationMs)ms")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)

                                                Spacer()

                                                Text(entry.finishedAt.formatted(date: .omitted, time: .standard))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }

                                            Text(entry.url)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)

                                            if let requestId = entry.requestId, !requestId.isEmpty {
                                                Text("request-id: \(requestId)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }

                                            if let message = entry.message, !message.isEmpty {
                                                Text(message)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(6)
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }
                            .frame(maxHeight: 260)
                            .border(.quaternary)
                            .textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, 6)
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

                            Button(mainShellStateStore.isRunningTask ? "Running..." : "Run Task") {
                                mainShellStateStore.startRunTaskNow()
                                if mainShellStateStore.isRunningTask {
                                    minimizeAppWindowsForRun()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(mainShellStateStore.isRunningTask || mainShellStateStore.isExtractingTask)

                            Button("Stop") {
                                mainShellStateStore.stopRunTask()
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .disabled(!mainShellStateStore.isRunningTask)
                        }

                        if let saveStatusMessage = mainShellStateStore.saveStatusMessage {
                            Text(saveStatusMessage)
                                .foregroundStyle(.green)
                        }

                        if let runStatusMessage = mainShellStateStore.runStatusMessage {
                            Text(runStatusMessage)
                                .foregroundStyle(.green)
                        }

                        Divider()
                            .padding(.vertical, 6)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Clarifications")
                                    .font(.headline)
                                Spacer()
                                Button("Refresh Questions") {
                                    mainShellStateStore.refreshClarificationQuestions()
                                }
                                .buttonStyle(.bordered)
                            }

                            if let clarificationStatusMessage = mainShellStateStore.clarificationStatusMessage {
                                Text(clarificationStatusMessage)
                                    .foregroundStyle(.green)
                            }

                            if mainShellStateStore.clarificationQuestions.isEmpty {
                                Text("No clarification questions found in HEARTBEAT.md.")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Open: \(mainShellStateStore.unresolvedClarificationQuestions.count) · Resolved: \(mainShellStateStore.resolvedClarificationQuestions.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if mainShellStateStore.unresolvedClarificationQuestions.isEmpty {
                                    Text("All clarification questions are resolved.")
                                        .foregroundStyle(.green)
                                } else {
                                    List(
                                        selection: Binding(
                                            get: { mainShellStateStore.selectedClarificationQuestionID },
                                            set: { mainShellStateStore.selectClarificationQuestion($0) }
                                        )
                                    ) {
                                        ForEach(mainShellStateStore.unresolvedClarificationQuestions) { question in
                                            Text(question.prompt)
                                                .tag(question.id)
                                        }
                                    }
                                    .frame(minHeight: 110, maxHeight: 180)

                                    if let selectedClarificationQuestion = mainShellStateStore.selectedClarificationQuestion {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Selected Question")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                            Text(selectedClarificationQuestion.prompt)
                                                .foregroundStyle(.secondary)
                                            TextField(
                                                "Type your answer",
                                                text: $mainShellStateStore.clarificationAnswerDraft,
                                                axis: .vertical
                                            )
                                            .lineLimit(2...5)
                                            .textFieldStyle(.roundedBorder)
                                            Button("Apply Answer") {
                                                mainShellStateStore.applyClarificationAnswer()
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .disabled(
                                                mainShellStateStore.selectedClarificationQuestion == nil ||
                                                mainShellStateStore.clarificationAnswerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                            )
                                        }
                                    }
                                }
                            }
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

    private func minimizeAppWindowsForRun() {
        // Minimize the main UI windows so the agent can operate without the app covering the desktop.
        // Keep overlay windows (borderless/HUD) visible.
        for window in NSApplication.shared.windows {
            guard window.isVisible else { continue }
            guard window.styleMask.contains(.titled) else { continue }
            window.miniaturize(nil)
        }
    }

    private func color(for kind: ExecutionTraceKind) -> Color {
        switch kind {
        case .info:
            return .secondary
        case .llmResponse:
            return .indigo
        case .toolUse:
            return .blue
        case .localAction:
            return .green
        case .completion:
            return .green
        case .cancelled:
            return .orange
        case .error:
            return .red
        }
    }
}
