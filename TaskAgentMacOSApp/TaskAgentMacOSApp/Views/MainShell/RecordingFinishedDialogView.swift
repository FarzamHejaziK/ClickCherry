import AVKit
import SwiftUI

struct RecordingFinishedDialogView: View {
    let recording: RecordingRecord
    let isExtracting: Bool
    let statusMessage: String?
    let errorMessage: String?
    let llmUserFacingIssue: LLMUserFacingIssue?
    @Binding var missingProviderKeyDialog: MissingProviderKeyDialog?
    let onRecordAgain: () -> Void
    let onExtractTask: () -> Void
    let onDismissMissingProviderKeyDialog: () -> Void
    let onOpenSettingsForMissingProviderKeyDialog: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var playerSetupWorkItem: DispatchWorkItem?

    var body: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)

            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.16),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 16) {
                header

                playerArea
                    .frame(width: 720, height: 420)

                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
            .allowsHitTesting(missingProviderKeyDialog == nil)

            if let dialog = missingProviderKeyDialog {
                MissingProviderKeyDialogCanvasView(
                    dialog: dialog,
                    onDismiss: {
                        self.missingProviderKeyDialog = nil
                        onDismissMissingProviderKeyDialog()
                    },
                    onOpenSettings: {
                        self.missingProviderKeyDialog = nil
                        onOpenSettingsForMissingProviderKeyDialog()
                    }
                )
                .zIndex(2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .onAppear {
            schedulePlayerConfigurationIfPossible()
        }
        .onDisappear {
            playerSetupWorkItem?.cancel()
            playerSetupWorkItem = nil
            player?.pause()
            player = nil
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                Image(systemName: "video.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.95))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text("Recording ready")
                    .font(.system(size: 20, weight: .semibold))

                if isExtracting {
                    Text("Extracting task from this recording…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Extract task to create a new task from this recording.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let statusMessage, isExtracting {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let llmUserFacingIssue {
                    Text(llmUserFacingIssue.detail)
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.9))
                        .lineLimit(3)
                } else if let errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.9))
                        .lineLimit(3)
                }
            }

            Spacer(minLength: 0)

            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Back to app")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isExtracting)
            .opacity(isExtracting ? 0.5 : 1.0)
        }
    }

    @ViewBuilder
    private var playerArea: some View {
        let exists = FileManager.default.fileExists(atPath: recording.fileURL.path)
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )

            if exists, let player {
                RecordingPreviewPlayerView(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(.secondary)
                    Text("Preview will appear when the recording file is available.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if isExtracting {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.26))
                    .overlay(
                        TaskExtractionProgressCanvasView(
                            title: "Extracting task from recording",
                            detail: statusMessage ?? "Analyzing content and preparing HEARTBEAT.md"
                        )
                        .padding(.horizontal, 34)
                        .padding(.vertical, 20)
                    )
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                onRecordAgain()
            } label: {
                Label("Record again", systemImage: "arrow.counterclockwise")
            }
            .ccPrimaryActionButton()
            .disabled(isExtracting)

            Spacer(minLength: 0)

            Button {
                onExtractTask()
            } label: {
                if isExtracting {
                    Label("Extracting…", systemImage: "sparkles")
                } else {
                    Label("Extract task", systemImage: "sparkles")
                }
            }
            .ccPrimaryActionButton()
            .keyboardShortcut(.defaultAction)
            .disabled(isExtracting)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func schedulePlayerConfigurationIfPossible() {
        playerSetupWorkItem?.cancel()
        playerSetupWorkItem = nil

        guard FileManager.default.fileExists(atPath: recording.fileURL.path) else {
            player = nil
            return
        }

        let setupWorkItem = DispatchWorkItem {
            guard FileManager.default.fileExists(atPath: recording.fileURL.path) else {
                player = nil
                return
            }
            player = AVPlayer(url: recording.fileURL)
        }
        playerSetupWorkItem = setupWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: setupWorkItem)
    }
}
