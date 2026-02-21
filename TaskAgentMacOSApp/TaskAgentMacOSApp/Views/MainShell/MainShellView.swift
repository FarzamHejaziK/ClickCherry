import Foundation
import SwiftUI

struct MainShellView: View {
    @State private var mainShellStateStore: MainShellStateStore

    init(mainShellStateStore: MainShellStateStore = MainShellStateStore()) {
        _mainShellStateStore = State(initialValue: mainShellStateStore)
    }

    var body: some View {
        ZStack {
            MainShellBackdropView()

            if mainShellStateStore.route == .settings {
                ZStack {
                    MainShellDetailBackdropView()
                    MainShellSettingsView(mainShellStateStore: mainShellStateStore)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    MainShellSidebarView(mainShellStateStore: mainShellStateStore)
                        .frame(minWidth: 240, idealWidth: 260, maxWidth: 320, maxHeight: .infinity)

                    MainShellDetailView(mainShellStateStore: mainShellStateStore)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            if let dialog = mainShellStateStore.missingProviderKeyDialog, mainShellStateStore.finishedRecordingReview == nil {
                MissingProviderKeyDialogCanvasView(
                    dialog: dialog,
                    onDismiss: {
                        mainShellStateStore.dismissMissingProviderKeyDialog()
                    },
                    onOpenSettings: {
                        mainShellStateStore.openSettingsForMissingProviderKeyDialog()
                    }
                )
                .zIndex(100)
            }
        }
        .onAppear {
            mainShellStateStore.reloadTasks()
            mainShellStateStore.refreshProviderKeysState()
            mainShellStateStore.refreshCaptureDisplays()
            mainShellStateStore.refreshCaptureAudioInputs()
        }
        .sheet(item: $mainShellStateStore.finishedRecordingReview, onDismiss: {
            mainShellStateStore.handleFinishedRecordingSheetDismissed()
        }) { review in
            RecordingFinishedDialogView(
                recording: review.recording,
                isExtracting: mainShellStateStore.isExtractingTask && mainShellStateStore.extractingRecordingID == review.recording.id,
                statusMessage: mainShellStateStore.extractionStatusMessage,
                errorMessage: mainShellStateStore.errorMessage,
                llmUserFacingIssue: mainShellStateStore.activeLLMUserFacingIssue,
                missingProviderKeyDialog: mainShellStateStore.missingProviderKeyDialog,
                onRecordAgain: {
                    mainShellStateStore.recordAgainFromFinishedRecordingDialog()
                },
                onExtractTask: {
                    mainShellStateStore.extractTaskFromFinishedRecordingDialog()
                },
                onDismissMissingProviderKeyDialog: {
                    mainShellStateStore.dismissMissingProviderKeyDialog()
                },
                onOpenSettingsForMissingProviderKeyDialog: {
                    mainShellStateStore.openSettingsForMissingProviderKeyDialog()
                },
                onOpenSettingsForLLMIssue: {
                    mainShellStateStore.openSettingsForActiveLLMUserFacingIssue()
                },
                onOpenProviderConsoleForLLMIssue: {
                    mainShellStateStore.openProviderConsoleForActiveLLMUserFacingIssue()
                }
            )
            .frame(width: 780, height: 560)
            .interactiveDismissDisabled(mainShellStateStore.isExtractingTask && mainShellStateStore.extractingRecordingID == review.recording.id)
        }
        .sheet(
            isPresented: Binding(
                get: {
                    mainShellStateStore.recordingPreflightDialogState != nil
                        && mainShellStateStore.finishedRecordingReview == nil
                },
                set: { isPresented in
                    if !isPresented {
                        mainShellStateStore.dismissRecordingPreflightDialog()
                    }
                }
            )
        ) {
            if let state = mainShellStateStore.recordingPreflightDialogState {
                RecordingPreflightDialogCanvasView(
                    showsBackdrop: true,
                    state: state,
                    apiKeyStatusMessage: mainShellStateStore.apiKeyStatusMessage,
                    apiKeyErrorMessage: mainShellStateStore.apiKeyErrorMessage,
                    onDismiss: {
                        mainShellStateStore.dismissRecordingPreflightDialog()
                    },
                    onOpenSettingsForRequirement: { requirement in
                        mainShellStateStore.openSettingsForRecordingPreflightRequirement(requirement)
                    },
                    onSaveGeminiKey: { key in
                        _ = mainShellStateStore.saveGeminiKeyFromRecordingPreflight(key)
                    },
                    onContinue: {
                        mainShellStateStore.continueAfterRecordingPreflightDialog()
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .presentationBackground(.clear)
                .interactiveDismissDisabled(false)
            }
        }
        .sheet(
            isPresented: Binding(
                get: {
                    mainShellStateStore.runTaskPreflightDialogState != nil
                        && mainShellStateStore.finishedRecordingReview == nil
                },
                set: { isPresented in
                    if !isPresented {
                        mainShellStateStore.dismissRunTaskPreflightDialog()
                    }
                }
            )
        ) {
            if let state = mainShellStateStore.runTaskPreflightDialogState {
                RunTaskPreflightDialogCanvasView(
                    showsBackdrop: true,
                    state: state,
                    apiKeyStatusMessage: mainShellStateStore.apiKeyStatusMessage,
                    apiKeyErrorMessage: mainShellStateStore.apiKeyErrorMessage,
                    onDismiss: {
                        mainShellStateStore.dismissRunTaskPreflightDialog()
                    },
                    onOpenSettingsForRequirement: { requirement in
                        mainShellStateStore.openSettingsForRunTaskPreflightRequirement(requirement)
                    },
                    onSaveOpenAIKey: { key in
                        _ = mainShellStateStore.saveOpenAIKeyFromRunTaskPreflight(key)
                    },
                    onContinue: {
                        mainShellStateStore.continueAfterRunTaskPreflightDialog()
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .presentationBackground(.clear)
                .interactiveDismissDisabled(false)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: mainShellStateStore.missingProviderKeyDialog != nil)
        .animation(.easeInOut(duration: 0.18), value: mainShellStateStore.recordingPreflightDialogState != nil)
        .animation(.easeInOut(duration: 0.18), value: mainShellStateStore.runTaskPreflightDialogState != nil)
    }
}

struct MainShellDetailView: View {
    @Bindable var mainShellStateStore: MainShellStateStore

    var body: some View {
        ZStack {
            switch mainShellStateStore.route {
            case .newTask:
                NewTaskEmptyView(mainShellStateStore: mainShellStateStore)
            case .task:
                TaskDetailView(mainShellStateStore: mainShellStateStore)
            case .settings:
                // Settings is rendered at the main-shell root so it can own the left column menu.
                EmptyView()
            }
        }
        .background {
            MainShellDetailBackdropView()
        }
    }
}

private struct MainShellDetailBackdropView: View {
    var body: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)

            // A subtle tint/vignette so the detail panel matches onboarding's accent palette.
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.08),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.black.opacity(0.12),
                    Color.clear
                ],
                center: .top,
                startRadius: 140,
                endRadius: 900
            )
            .blendMode(.multiply)
        }
    }
}
