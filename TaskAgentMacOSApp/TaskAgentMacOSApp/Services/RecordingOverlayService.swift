import AppKit

protocol RecordingOverlayService {
    func showBorder(displayID: Int)
    func hideBorder()
}

final class ScreenRecordingOverlayService: RecordingOverlayService {
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

    private var overlayWindow: NSWindow?

    func showBorder(displayID: Int) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.showBorder(displayID: displayID)
            }
            return
        }

        hideBorder()
        guard let screen = screenForDisplayID(displayID) else {
            return
        }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = BorderView(frame: NSRect(origin: .zero, size: screen.frame.size))
        window.orderFrontRegardless()
        overlayWindow = window
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
    }

    private func screenForDisplayID(_ displayID: Int) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let raw = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            let screenID = CGDirectDisplayID(raw.uint32Value)
            let expected = displayIDFromScreenID(screenID)
            return expected == displayID
        }
    }

    private func displayIDFromScreenID(_ screenID: CGDirectDisplayID) -> Int? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return nil
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
            return nil
        }

        for (index, activeID) in displays.enumerated() where activeID == screenID {
            return index + 1
        }
        return nil
    }
}
