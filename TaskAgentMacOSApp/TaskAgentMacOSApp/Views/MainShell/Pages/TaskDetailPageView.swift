import AppKit
import CoreGraphics
import Foundation
import SwiftUI

struct TaskDetailView: View {
    @Bindable var mainShellStateStore: MainShellStateStore
    @State private var isTaskDetailsExpanded: Bool = true
    private let pageContentMaxWidth: CGFloat = 1120

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let selectedTask = mainShellStateStore.selectedTask {
                    heroRun(selectedTask: selectedTask)

                    heartbeatEditorCard(selectedTask: selectedTask)

                    runsCard()
                } else {
                    Text("Select a task from the sidebar.")
                        .foregroundStyle(.secondary)
                }
            }
            // Keep content centered on wide/fullscreen windows (avoid edge-to-edge stretching).
            .frame(maxWidth: pageContentMaxWidth, alignment: .topLeading)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.never)
        .onAppear {
            mainShellStateStore.refreshCaptureDisplays()
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

    private func heroRun(selectedTask: TaskRecord) -> some View {
        VStack(spacing: 12) {
            VStack(spacing: 6) {
                Text("Run task")
                    .font(.system(size: 34, weight: .semibold))
                Text("A run is an agentic workflow.\nClickCherry uses this task spec to act on your screen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 880)

            Button {
                if mainShellStateStore.isRunningTask {
                    mainShellStateStore.stopRunTask()
                    return
                }
                mainShellStateStore.startRunTaskNow()
                if mainShellStateStore.isRunningTask {
                    minimizeAppWindowsForRun()
                }
            } label: {
                Image(systemName: mainShellStateStore.isRunningTask ? "stop.fill" : "play.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(mainShellStateStore.isRunningTask ? Color.red : Color.primary)
                    .frame(width: 72, height: 72)
                    .background(.thinMaterial, in: Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(mainShellStateStore.isExtractingTask)

            if !mainShellStateStore.isRunningTask, mainShellStateStore.availableCaptureDisplays.count > 1 {
                RunDisplayPickerView(mainShellStateStore: mainShellStateStore)
                    .padding(.top, 4)
            }

            if let runStatusMessage = mainShellStateStore.runStatusMessage {
                StatusLine(kind: .info, text: runStatusMessage)
            } else if let errorMessage = mainShellStateStore.errorMessage, !errorMessage.isEmpty {
                StatusLine(kind: .error, text: errorMessage)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func heartbeatEditorCard(selectedTask: TaskRecord) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                DisclosureGroup(isExpanded: $isTaskDetailsExpanded) {
                    TextEditor(text: $mainShellStateStore.heartbeatMarkdown)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(minHeight: 280)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        )
                        .padding(.top, 8)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Text("Task")
                            .font(.headline)

                        Spacer(minLength: 0)

                        Button {
                            mainShellStateStore.saveSelectedTaskHeartbeat()
                        } label: {
                            Label("Save", systemImage: "checkmark")
                        }
                        .ccPrimaryActionButton()
                    }
                    .contentShape(Rectangle())
                }
                .disclosureGroupStyle(.automatic)

                HStack(spacing: 10) {
                    if let saveStatusMessage = mainShellStateStore.saveStatusMessage {
                        StatusLine(kind: .success, text: saveStatusMessage)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func runsCard() -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Runs")
                    .font(.headline)

                if mainShellStateStore.runHistory.isEmpty {
                    Text("No runs yet.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(mainShellStateStore.runHistory.enumerated()), id: \.element.id) { idx, run in
                            DisclosureGroup {
                                RunLogListView(events: run.events)
                                    .padding(.top, 6)
                            } label: {
                                RunHeaderView(title: "Run \(idx + 1)", run: run)
                            }
                            .disclosureGroupStyle(.automatic)
                        }
                    }
                }
            }
        }
    }
}

private struct RunDisplayPickerView: View {
    @Bindable var mainShellStateStore: MainShellStateStore
    @State private var thumbnailsByDisplayIndex: [Int: CGImage] = [:]

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("Screen")
                    .font(.headline)
                    .foregroundStyle(.primary.opacity(0.9))

                Text("Pick the screen for the agent.\nScreenshots and actions use this display.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 760)
            }

            let displays = mainShellStateStore.availableCaptureDisplays
            if displays.count <= 3 {
                HStack(spacing: 18) {
                    ForEach(displays) { display in
                        DisplayThumbnailCard(
                            label: display.label,
                            thumbnail: thumbnailsByDisplayIndex[display.id],
                            isSelected: mainShellStateStore.selectedRunDisplayID == display.id,
                            onSelect: {
                                mainShellStateStore.selectedRunDisplayID = display.id
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(displays) { display in
                            DisplayThumbnailCard(
                                label: display.label,
                                thumbnail: thumbnailsByDisplayIndex[display.id],
                                isSelected: mainShellStateStore.selectedRunDisplayID == display.id,
                                onSelect: {
                                    mainShellStateStore.selectedRunDisplayID = display.id
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .frame(height: 150)
            }
        }
        .frame(maxWidth: 920)
        .onAppear {
            refreshThumbnails()
        }
        .onChange(of: mainShellStateStore.availableCaptureDisplays) { _ in
            refreshThumbnails()
        }
    }

    private func refreshThumbnails() {
        let displayIndices = mainShellStateStore.availableCaptureDisplays.map(\.id)
        guard !displayIndices.isEmpty else {
            thumbnailsByDisplayIndex = [:]
            return
        }

        Task.detached(priority: .utility) {
            var next: [Int: CGImage] = [:]
            for displayIndex in displayIndices {
                if let thumbnail = try? DisplayThumbnailService.captureThumbnailForDisplayIndex(displayIndex) {
                    next[displayIndex] = thumbnail
                }
            }
            await MainActor.run {
                thumbnailsByDisplayIndex = next
            }
        }
    }
}

private struct DisplayThumbnailCard: View {
    let label: String
    let thumbnail: CGImage?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let thumbnail {
                        Image(decorative: thumbnail, scale: 1.0, orientation: .up)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            Color.black.opacity(0.22)
                            Image(systemName: "display")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }
                }
                .frame(width: 220, height: 138)
                .clipped()

                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.58)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack(spacing: 10) {
                    Image(systemName: "display")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))

                    Text(label)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.94))

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(width: 220, height: 138)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.95) : Color.primary.opacity(0.14),
                        lineWidth: isSelected ? 1.6 : 1
                    )
            )
            .overlay(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(isSelected ? 0.16 : 0.06),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct RunDetailsHeader: View {
    let icon: String
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Spacer(minLength: 0)
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct RunHeaderView: View {
    let title: String
    let run: AgentRunRecord

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Spacer(minLength: 0)

            if let started = run.startedAt as Date? {
                Text(Self.dateTimeFormatter.string(from: started))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct RunLogListView: View {
    let events: [AgentRunEvent]

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func kindColor(_ kind: AgentRunEvent.Kind) -> Color {
        switch kind {
        case .error:
            return .red.opacity(0.9)
        case .cancelled:
            return .orange.opacity(0.9)
        case .completion:
            return .green.opacity(0.9)
        case .tool:
            return .accentColor.opacity(0.95)
        case .llm:
            return .secondary
        case .action:
            return .secondary
        case .info:
            return .secondary
        }
    }

    var body: some View {
        if events.isEmpty {
            Text("No log entries yet.")
                .foregroundStyle(.secondary)
                .font(.callout)
                .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(events) { event in
                    HStack(alignment: .top, spacing: 10) {
                        Text(Self.timeFormatter.string(from: event.timestamp))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .leading)

                        Text(event.kind.rawValue.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(kindColor(event.kind))
                            .frame(width: 86, alignment: .leading)

                        Text(event.message)
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(0.92))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

private struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}

private struct StatusLine: View {
    enum Kind {
        case info
        case success
        case warning
        case error

        var color: Color {
            switch self {
            case .info:
                return .secondary
            case .success:
                return .green
            case .warning:
                return .orange
            case .error:
                return .red
            }
        }

        var icon: String {
            switch self {
            case .info:
                return "info.circle"
            case .success:
                return "checkmark.circle.fill"
            case .warning:
                return "exclamationmark.triangle.fill"
            case .error:
                return "xmark.octagon.fill"
            }
        }
    }

    let kind: Kind
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: kind.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(kind.color.opacity(0.95))
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.10))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .frame(maxWidth: 880, alignment: .center)
    }
}
