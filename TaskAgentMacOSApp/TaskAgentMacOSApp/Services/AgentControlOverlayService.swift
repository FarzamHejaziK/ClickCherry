import AppKit
import SwiftUI

enum AgentControlOverlayPhase: String, Equatable, Sendable {
    case running
    case stopping
}

enum AgentControlOverlayActivityState: String, Equatable, Sendable {
    case starting
    case thinking
    case usingTool
    case acting
    case capturing
    case completing
    case error
    case stopping
}

struct AgentControlOverlaySnapshot: Equatable, Sendable {
    var headline: String
    var stopReason: String?
    var events: [AgentRunEvent]
    var screenshots: [LLMScreenshotLogEntry]
    var startedAt: Date
    var latestActivityAt: Date
    var activityState: AgentControlOverlayActivityState

    init(
        headline: String,
        stopReason: String? = nil,
        events: [AgentRunEvent] = [],
        screenshots: [LLMScreenshotLogEntry] = [],
        startedAt: Date = Date(),
        latestActivityAt: Date? = nil,
        activityState: AgentControlOverlayActivityState = .starting
    ) {
        self.headline = headline
        self.stopReason = stopReason
        self.events = events
        self.screenshots = screenshots
        self.startedAt = startedAt
        self.latestActivityAt = latestActivityAt ?? startedAt
        self.activityState = activityState
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

        var height: CGFloat = 168
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
        TimelineView(.animation(minimumInterval: 0.35, paused: false)) { context in
            let now = context.date

            VStack(alignment: .leading, spacing: 12) {
                headerRow(at: now)
                activityRail(at: now)
                liveStatusCard(at: now)

                if !visibleEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(visibleEvents) { event in
                            overlayEventRow(event)
                        }
                    }
                }

                screenshotsSection(at: now)
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
    }

    private func headerRow(at now: Date) -> some View {
        HStack(alignment: .top, spacing: 12) {
            statusChip(at: now)

            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.96))
                Text(secondaryStatusText)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.68))
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(elapsedText(at: now))
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.68))
                Text("Overlay hidden from agent screenshots")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.42))
            }
        }
    }

    private func statusChip(at now: Date) -> some View {
        HStack(spacing: 7) {
            spinner(at: now)
            Text(phase == .running ? "LIVE" : "STOPPING")
                .font(.system(size: 10.5, weight: .bold))
        }
        .foregroundStyle(Color.white.opacity(0.92))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(activityAccentColor.opacity(phase == .running ? 0.11 : 0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(activityAccentColor.opacity(phase == .running ? 0.22 : 0.22), lineWidth: 1)
        )
    }

    private func spinner(at now: Date) -> some View {
        Circle()
            .trim(from: 0.14, to: 0.84)
            .stroke(activityAccentColor.opacity(0.96), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .frame(width: 10, height: 10)
            .rotationEffect(.degrees(now.timeIntervalSinceReferenceDate * (phase == .running ? 220 : 110)))
    }

    private func activityRail(at now: Date) -> some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let segmentWidth = max(82, width * 0.22)
            let cycleDuration = phase == .running ? 1.45 : 2.3
            let progress = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
            let xOffset = (width + segmentWidth) * progress - segmentWidth

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.05))

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                activityAccentColor.opacity(0.00),
                                activityAccentColor.opacity(0.28),
                                activityAccentColor.opacity(0.90),
                                activityAccentColor.opacity(0.18)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: segmentWidth)
                    .offset(x: xOffset)
            }
        }
        .frame(height: 5)
        .clipShape(Capsule(style: .continuous))
    }

    private func liveStatusCard(at now: Date) -> some View {
        let age = max(0, now.timeIntervalSince(snapshot.latestActivityAt))
        let freshness = max(0.0, 1.0 - min(age, 2.0) / 2.0)
        let pulse = 0.5 + 0.5 * sin(now.timeIntervalSinceReferenceDate * 3.8)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(liveVerb(at: now) + animatedDots(at: now))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(activityAccentColor.opacity(0.95))

                Text(lastActivityText(at: now))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.48))

                Spacer(minLength: 0)

                if let newestEvent {
                    eventKindBadge(for: newestEvent.kind)
                }
            }

            Text(snapshot.headline)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.98))
                .lineLimit(2)

            HStack(spacing: 8) {
                Text(rotatingTip(at: now))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.64))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(Self.timeFormatter.string(from: snapshot.latestActivityAt))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.42))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.018 + (freshness * pulse * 0.030)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(activityAccentColor.opacity(0.05 + freshness * 0.14), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func screenshotsSection(at now: Date) -> some View {
        if !visibleScreenshots.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Recent model-visible screenshots")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.56))
                    Text("streaming")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(activityAccentColor.opacity(0.92))
                }

                HStack(spacing: 10) {
                    ForEach(Array(visibleScreenshots.enumerated()), id: \.element.id) { offset, screenshot in
                        screenshotCard(screenshot, isNewest: offset == 0, now: now)
                    }
                }
            }
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

    private func screenshotCard(_ entry: LLMScreenshotLogEntry, isNewest: Bool, now: Date) -> some View {
        let age = max(0, now.timeIntervalSince(entry.timestamp))
        let isFresh = isNewest && age < 2.5
        let pulse = 0.5 + 0.5 * sin(now.timeIntervalSinceReferenceDate * 4.5)

        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                screenshotImage(for: entry)
                    .frame(width: 128, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                if isFresh {
                    Text("Just captured")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.96))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(activityAccentColor.opacity(0.40 + pulse * 0.20))
                        )
                        .padding(6)
                }
            }

            Text("\(entry.source.rawValue) • \(Self.timeFormatter.string(from: entry.timestamp))")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.54))
                .lineLimit(1)
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.015 + (isFresh ? pulse * 0.020 : 0)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke((isFresh ? activityAccentColor : Color.white).opacity(isFresh ? 0.22 + pulse * 0.10 : 0.03), lineWidth: 1)
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

    private var activityAccentColor: Color {
        switch snapshot.activityState {
        case .starting, .thinking:
            return .mint
        case .usingTool:
            return .blue
        case .acting:
            return .yellow
        case .capturing:
            return .cyan
        case .completing:
            return .green
        case .error:
            return .red
        case .stopping:
            return .orange
        }
    }

    private func liveVerb(at now: Date) -> String {
        switch snapshot.activityState {
        case .starting:
            return "Starting"
        case .thinking:
            return "Thinking"
        case .usingTool:
            return "Using tool"
        case .acting:
            return "Taking action"
        case .capturing:
            return "Capturing"
        case .completing:
            return "Wrapping up"
        case .error:
            return "Needs attention"
        case .stopping:
            return "Stopping"
        }
    }

    private func rotatingTip(at now: Date) -> String {
        let tips: [String]
        switch snapshot.activityState {
        case .starting:
            tips = [
                "Preparing the live takeover",
                "Waiting for the first run event",
                "Bringing the overlay online"
            ]
        case .thinking:
            tips = [
                "Reading the latest screen state",
                "Planning the next step",
                "Waiting for model output"
            ]
        case .usingTool:
            tips = [
                "Running the current tool call",
                "Collecting tool output",
                "Streaming tool results back"
            ]
        case .acting:
            tips = [
                "Applying the next UI step",
                "Sending the next desktop action",
                "Updating the visible state"
            ]
        case .capturing:
            tips = [
                "Refreshing the model-visible snapshot",
                "Recording the newest frame",
                "Saving the latest screen state"
            ]
        case .completing:
            tips = [
                "Finishing the current task",
                "Writing the final result",
                "Cleaning up the live run"
            ]
        case .error:
            tips = [
                "Holding the latest context on screen",
                "Waiting for the next recovery step",
                "Keeping the current failure visible"
            ]
        case .stopping:
            tips = [
                "Waiting for the active step to settle",
                "Letting the current action unwind",
                "Keeping the last context visible"
            ]
        }

        let index = Int(now.timeIntervalSinceReferenceDate / 2.8) % max(tips.count, 1)
        return tips[index]
    }

    private func animatedDots(at now: Date) -> String {
        let count = Int(now.timeIntervalSinceReferenceDate * (phase == .running ? 1.8 : 0.9)) % 4
        guard count > 0 else { return "" }
        return String(repeating: ".", count: count)
    }

    private func elapsedText(at now: Date) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(snapshot.startedAt)))
        return "LIVE \(formatDuration(elapsed))"
    }

    private func lastActivityText(at now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(snapshot.latestActivityAt)))
        if seconds == 0 {
            return "updating now"
        }
        if seconds == 1 {
            return "updated 1s ago"
        }
        return "updated \(seconds)s ago"
    }

    private func formatDuration(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
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
