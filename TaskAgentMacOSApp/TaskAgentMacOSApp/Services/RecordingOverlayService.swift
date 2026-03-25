import AppKit
import CoreGraphics

protocol RecordingOverlayService {
    func showBorder(displayID: Int)
    func hideBorder()
    func windowNumberForScreenshotExclusion() -> Int?
}

final class ScreenRecordingOverlayService: RecordingOverlayService {
    private final class BorderPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class BorderView: NSView {
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderColor = NSColor.systemRed.cgColor
            layer?.borderWidth = 8
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    private var overlayWindow: BorderPanel?
    private var overlayWindowNumber: Int?
    private var activationObserver: NSObjectProtocol?

    func showBorder(displayID: Int) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.showBorder(displayID: displayID)
            }
            return
        }

        hideBorder()
        guard let screen = ScreenDisplayIndexService.screenForScreencaptureDisplayIndex(displayID)
            ?? NSScreen.screens.first else {
            return
        }

        let window = BorderPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("cc.overlay.recordingBorder")
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        // Keep visible even if the app deactivates while other apps are used during recording.
        window.hidesOnDeactivate = false
        // Keep visible to the user but do not include in recording output.
        window.sharingType = .none
        // Use a high level so the border remains visible above full-screen and presentation layers.
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isFloatingPanel = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = BorderView(frame: NSRect(origin: .zero, size: screen.frame.size))
        window.orderFrontRegardless()
        overlayWindow = window
        overlayWindowNumber = window.windowNumber
        ensureActivationObserver()
    }

    func hideBorder() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.hideBorder()
            }
            return
        }
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        overlayWindowNumber = nil

        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    func windowNumberForScreenshotExclusion() -> Int? {
        // Use the cached window number so this method is safe off-main-thread.
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

    // Screen indexing is handled by `ScreenDisplayIndexService`.
}
