import AppKit
import SwiftUI

enum AgentControlOverlayPhase: String, Equatable, Sendable {
    case running
    case stopping
}

struct AgentControlOverlaySnapshot: Equatable, Sendable {
    var headline: String
    var stopReason: String?
    var events: [AgentRunEvent]
    var screenshots: [LLMScreenshotLogEntry]

    init(
        headline: String,
        stopReason: String? = nil,
        events: [AgentRunEvent] = [],
        screenshots: [LLMScreenshotLogEntry] = []
    ) {
        self.headline = headline
        self.stopReason = stopReason
        self.events = events
        self.screenshots = screenshots
    }
}

protocol AgentControlOverlayService {
    func showAgentInControl(displayID: Int?)
    func updateAgentInControl(snapshot: AgentControlOverlaySnapshot, phase: AgentControlOverlayPhase)
    func hideAgentInControl()
    /// If non-nil, callers may exclude this window from screenshots (e.g. for LLM tool-loop captures).
    func windowNumberForScreenshotExclusion() -> Int?
}

final class HUDWindowAgentControlOverlayService: AgentControlOverlayService {
    private final class HUDPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private var overlayWindow: HUDPanel?
    private var overlayWindowNumber: Int?
    private var hostingView: NSHostingView<AgentControlOverlayRailView>?
    private var activationObserver: NSObjectProtocol?
    private var currentDisplayID: Int?
    private var currentPhase: AgentControlOverlayPhase = .running
    private var currentSnapshot = AgentControlOverlaySnapshot(headline: "Agent is running")

    func showAgentInControl(displayID: Int?) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.showAgentInControl(displayID: displayID)
            }
            return
        }

        currentDisplayID = displayID
        let targetScreen = preferredScreen(displayID: displayID)
        let size = overlaySize(for: currentSnapshot, phase: currentPhase, on: targetScreen.visibleFrame)
        let frame = topCenteredFrame(size: size, on: targetScreen.visibleFrame, yOffsetFromTop: 18)

        if let window = overlayWindow {
            window.setFrame(frame, display: true)
            hostingView?.frame = NSRect(origin: .zero, size: size)
            window.orderFrontRegardless()
            ensureActivationObserver()
            return
        }

        let window = HUDPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("cc.overlay.agentControlHUD")
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 1.0
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.sharingType = .none
        // Keep above normal app windows while still click-through and non-activating.
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.isFloatingPanel = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none

        let hostingView = NSHostingView(
            rootView: AgentControlOverlayRailView(snapshot: currentSnapshot, phase: currentPhase)
        )
        hostingView.frame = NSRect(origin: .zero, size: size)
        window.contentView = hostingView
        window.orderFrontRegardless()

        overlayWindow = window
        overlayWindowNumber = window.windowNumber
        self.hostingView = hostingView
        ensureActivationObserver()
    }

    func updateAgentInControl(snapshot: AgentControlOverlaySnapshot, phase: AgentControlOverlayPhase) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updateAgentInControl(snapshot: snapshot, phase: phase)
            }
            return
        }

        currentSnapshot = snapshot
        currentPhase = phase

        guard let window = overlayWindow else {
            return
        }

        let targetScreen = window.screen ?? preferredScreen(displayID: currentDisplayID)
        let size = overlaySize(for: snapshot, phase: phase, on: targetScreen.visibleFrame)
        let frame = topCenteredFrame(size: size, on: targetScreen.visibleFrame, yOffsetFromTop: 18)
        window.setFrame(frame, display: true)
        hostingView?.frame = NSRect(origin: .zero, size: size)
        hostingView?.rootView = AgentControlOverlayRailView(snapshot: snapshot, phase: phase)
        window.orderFrontRegardless()
        ensureActivationObserver()
    }

    func hideAgentInControl() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.hideAgentInControl()
            }
            return
        }

        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        overlayWindowNumber = nil
        hostingView = nil
        currentDisplayID = nil
        currentPhase = .running
        currentSnapshot = AgentControlOverlaySnapshot(headline: "Agent is running")

        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    func windowNumberForScreenshotExclusion() -> Int? {
        overlayWindowNumber
    }

    private func ensureActivationObserver() {
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.overlayWindow?.orderFrontRegardless()
        }
    }

    private func topCenteredFrame(size: NSSize, on container: NSRect, yOffsetFromTop: CGFloat) -> NSRect {
        NSRect(
            x: container.midX - size.width / 2.0,
            y: container.maxY - yOffsetFromTop - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func overlaySize(for snapshot: AgentControlOverlaySnapshot, phase: AgentControlOverlayPhase, on container: NSRect) -> NSSize {
        let width = min(max(container.width - 40, 380), 620)
        let visibleEventCount: Int
        switch phase {
        case .running:
            visibleEventCount = min(max(snapshot.events.count - 1, 0), 5)
        case .stopping:
            visibleEventCount = min(snapshot.events.count, 5)
        }

        var height: CGFloat = 126
        height += CGFloat(visibleEventCount) * 24
        if snapshot.stopReason != nil {
            height += 18
        }
        if !snapshot.screenshots.isEmpty {
            height += 110
        }
        height = min(max(height, 148), max(container.height - 26, 148))
        return NSSize(width: width, height: height)
    }

    private func preferredScreen(displayID: Int?) -> NSScreen {
        if let displayID, let match = ScreenDisplayIndexService.screenForScreencaptureDisplayIndex(displayID) {
            return match
        }

        let screens = NSScreen.screens
        let mouseLocation = NSEvent.mouseLocation
        if let screen = screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screen
        }
        if let screen = NSScreen.main {
            return screen
        }
        // There is always at least one screen.
        return screens[0]
    }
}

private struct AgentControlOverlayRailView: View {
    let snapshot: AgentControlOverlaySnapshot
    let phase: AgentControlOverlayPhase

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var newestEvent: AgentRunEvent? {
        guard phase == .running else { return nil }
        return snapshot.events.first
    }

    private var visibleEvents: [AgentRunEvent] {
        switch phase {
        case .running:
            return Array(snapshot.events.dropFirst().prefix(5))
        case .stopping:
            return Array(snapshot.events.prefix(5))
        }
    }

    private var visibleScreenshots: [LLMScreenshotLogEntry] {
        Array(snapshot.screenshots.prefix(3))
    }

    private var statusTitle: String {
        switch phase {
        case .running:
            return "Agent running"
        case .stopping:
            return "Stopping"
        }
    }

    private var secondaryStatusText: String {
        switch phase {
        case .running:
            return "Press Escape to stop"
        case .stopping:
            if let stopReason = snapshot.stopReason, !stopReason.isEmpty {
                return stopReason
            }
            return "Waiting for the current run to settle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                statusChip

                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.96))
                    Text(secondaryStatusText)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.68))
                }

                Spacer(minLength: 0)

                Text("Overlay hidden from agent screenshots")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.42))
            }

            latestHeadline

            if !visibleEvents.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(visibleEvents) { event in
                        overlayEventRow(event)
                    }
                }
            }

            if !visibleScreenshots.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent model-visible screenshots")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.56))

                    HStack(spacing: 10) {
                        ForEach(visibleScreenshots) { screenshot in
                            screenshotCard(screenshot)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.32))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.10), radius: 14, x: 0, y: 8)
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private var statusChip: some View {
        Text(phase == .running ? "LIVE" : "STOPPING")
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.92))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(phase == .running ? Color.green.opacity(0.11) : Color.orange.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(phase == .running ? Color.green.opacity(0.22) : Color.orange.opacity(0.22), lineWidth: 1)
            )
    }

    private var latestHeadline: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let newestEvent {
                HStack(spacing: 8) {
                    eventKindBadge(for: newestEvent.kind)
                    Text(Self.timeFormatter.string(from: newestEvent.timestamp))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.54))
                }
            }

            Text(snapshot.headline)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.98))
                .lineLimit(2)
        }
    }

    private func overlayEventRow(_ event: AgentRunEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Self.timeFormatter.string(from: event.timestamp))
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.42))
                .frame(width: 56, alignment: .leading)

            eventKindBadge(for: event.kind)
                .frame(width: 72, alignment: .leading)

            Text(event.message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.76))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func eventKindBadge(for kind: AgentRunEvent.Kind) -> some View {
        Text(kind.rawValue.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(eventColor(for: kind))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(eventColor(for: kind).opacity(0.05))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(eventColor(for: kind).opacity(0.10), lineWidth: 1)
            )
    }

    private func screenshotCard(_ entry: LLMScreenshotLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            screenshotImage(for: entry)
                .frame(width: 128, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text("\(entry.source.rawValue) • \(Self.timeFormatter.string(from: entry.timestamp))")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.54))
                .lineLimit(1)
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.015))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.03), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func screenshotImage(for entry: LLMScreenshotLogEntry) -> some View {
        if let image = NSImage(data: entry.imageData) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.020))
                Image(systemName: "photo")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
        }
    }

    private func eventColor(for kind: AgentRunEvent.Kind) -> Color {
        switch kind {
        case .completion:
            return .green
        case .cancelled:
            return .orange
        case .error:
            return .red
        case .tool:
            return .blue
        case .llm:
            return .mint
        case .action:
            return .yellow
        case .info:
            return Color.white.opacity(0.78)
        }
    }
}
