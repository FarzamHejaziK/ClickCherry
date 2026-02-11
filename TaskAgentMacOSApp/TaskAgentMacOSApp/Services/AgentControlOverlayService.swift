import AppKit

protocol AgentControlOverlayService {
    func showAgentInControl()
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
    private var activationObserver: NSObjectProtocol?

    func showAgentInControl() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.showAgentInControl()
            }
            return
        }

        let targetScreen = preferredScreen()
        let size = NSSize(width: 360, height: 84)
        let frame = centeredFrame(size: size, on: targetScreen.visibleFrame)

        if let window = overlayWindow {
            window.setFrame(frame, display: true)
            window.orderFrontRegardless()
            ensureActivationObserver()
            return
        }

        let window = HUDPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: targetScreen
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 1.0
        window.hasShadow = true
        window.ignoresMouseEvents = true
        // Keep above normal app windows while still click-through and non-activating.
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.isFloatingPanel = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none

        window.contentView = makeContentView(size: size)
        window.orderFrontRegardless()

        overlayWindow = window
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

        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    func windowNumberForScreenshotExclusion() -> Int? {
        if Thread.isMainThread {
            return overlayWindow?.windowNumber
        }

        var value: Int?
        DispatchQueue.main.sync {
            value = overlayWindow?.windowNumber
        }
        return value
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

    private func centeredFrame(size: NSSize, on container: NSRect) -> NSRect {
        NSRect(
            x: container.midX - size.width / 2.0,
            y: container.midY - size.height / 2.0,
            width: size.width,
            height: size.height
        )
    }

    private func makeContentView(size: NSSize) -> NSView {
        let root = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        root.material = .hudWindow
        root.blendingMode = .withinWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 14
        root.layer?.masksToBounds = true
        root.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        root.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        root.layer?.borderWidth = 1

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)

        let title = NSTextField(labelWithString: "Agent is running")
        title.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        title.textColor = .white

        let subtitle = NSTextField(labelWithString: "Press Escape to stop")
        subtitle.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.85)

        let header = NSStackView(views: [spinner, title])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10

        let stack = NSStackView(views: [header, subtitle])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor)
        ])

        return root
    }

    private func preferredScreen() -> NSScreen {
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
