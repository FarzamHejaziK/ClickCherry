import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct TaskDetailView: View {
    @Bindable var mainShellStateStore: MainShellStateStore
    @State private var isRecordingImporterPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let selectedTask = mainShellStateStore.selectedTask {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(selectedTask.title)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Workspace: \(selectedTask.workspace.root.path)")
                            .foregroundStyle(.secondary)
                            .font(.caption)

                        Text("HEARTBEAT: \(selectedTask.workspace.heartbeatFile.lastPathComponent)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }

                    if let runStatusMessage = mainShellStateStore.runStatusMessage {
                        Text(runStatusMessage)
                            .foregroundStyle(.green)
                    }

                    if let saveStatusMessage = mainShellStateStore.saveStatusMessage {
                        Text(saveStatusMessage)
                            .foregroundStyle(.green)
                    }

                    if let errorMessage = mainShellStateStore.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("HEARTBEAT.md")
                            .font(.headline)

                        TextEditor(text: $mainShellStateStore.heartbeatMarkdown)
                            .font(.body.monospaced())
                            .frame(minHeight: 240)
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
                    }

                    Divider()

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

                    VStack(alignment: .leading, spacing: 10) {
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
                            .frame(width: 260)
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
                            .buttonStyle(.bordered)
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
                            .frame(minHeight: 140, maxHeight: 240)
                        }
                    }
                } else {
                    Text("Select a task from the sidebar.")
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(24)
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

    private func minimizeAppWindowsForRun() {
        // Minimize the main UI windows so the agent can operate without the app covering the desktop.
        // Keep overlay windows (borderless/HUD) visible.
        for window in NSApplication.shared.windows {
            guard window.isVisible else { continue }
            guard window.styleMask.contains(.titled) else { continue }
            window.miniaturize(nil)
        }
    }
}

