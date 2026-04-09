import AppKit
import CoreGraphics

protocol RecordingControlOverlayService {
    func showRecordingHint(displayID: Int?)
    func hideRecordingHint()
}

/// Click-through HUD shown during recording so the user can stop via Escape even when the app is minimized.
final class HUDWindowRecordingControlOverlayService: RecordingControlOverlayService {
    private final class HUDPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private var overlayWindow: HUDPanel?
    private var activationObserver: NSObjectProtocol?

    func showRecordingHint(displayID: Int?) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.showRecordingHint(displayID: displayID)
            }
            return
        }

        let targetScreen = preferredScreen(displayID: displayID)
        let size = NSSize(width: 340, height: 74)
        let frame = topCenteredFrame(size: size, on: targetScreen.visibleFrame, yOffsetFromTop: 86)

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
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("cc.overlay.recordingHintHUD")
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 1.0
        window.hasShadow = true
        window.ignoresMouseEvents = true
        // Ensure the hint is visible to the user but not captured into the recording.
        window.sharingType = .none
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

    func hideRecordingHint() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.hideRecordingHint()
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

    private func makeContentView(size: NSSize) -> NSView {
        let root = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        root.material = .hudWindow
        root.blendingMode = .withinWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 14
        root.layer?.masksToBounds = true
        root.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.30).cgColor
        root.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        root.layer?.borderWidth = 1

        let dot = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 5

        let title = NSTextField(labelWithString: "Recording")
        title.font = NSFont.systemFont(ofSize: 17, weight: .bold)
        title.textColor = .white

        let subtitle = NSTextField(labelWithString: "Press Escape to stop recording")
        subtitle.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.85)

        let header = NSStackView(views: [dot, title])
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

    private func preferredScreen(displayID: Int?) -> NSScreen {
        if let displayID, let match = ScreenDisplayIndexService.screenForScreencaptureDisplayIndex(displayID) {
            return match
        }
        if let main = NSScreen.main {
            return main
        }
        // There is always at least one screen.
        return NSScreen.screens[0]
    }
}
