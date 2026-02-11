import AppKit
import Foundation

protocol AgentCursorPresentationService {
    @discardableResult
    func activateTakeoverCursor() -> Bool

    @discardableResult
    func deactivateTakeoverCursor() -> Bool
}

final class AccessibilityAgentCursorPresentationService: AgentCursorPresentationService {
    private enum TakeoverPresentationMode {
        case systemCursorSize
        case overlayHalo
    }

    private let lock = NSLock()
    private let preferenceDomain: CFString = "com.apple.universalaccess" as CFString
    private let cursorSizeKey: CFString = "mouseDriverCursorSize" as CFString
    private let defaultCursorSize: Double = 1.0
    private let boostedCursorSize: Double
    private let cursorHaloOverlay = CursorHaloOverlay()

    private var activeTakeoverCount: Int = 0
    private var originalCursorSize: Double?
    private var activeMode: TakeoverPresentationMode?

    init(boostedCursorSize: Double = 4.0) {
        self.boostedCursorSize = max(boostedCursorSize, defaultCursorSize)
    }

    @discardableResult
    func activateTakeoverCursor() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if activeTakeoverCount > 0 {
            activeTakeoverCount += 1
            return true
        }

        let baseline = readCursorSize() ?? defaultCursorSize
        originalCursorSize = baseline
        activeTakeoverCount = 1

        let target = max(boostedCursorSize, baseline)
        if target == baseline {
            activeMode = .systemCursorSize
            return true
        }

        if writeCursorSize(target) {
            activeMode = .systemCursorSize
            return true
        }

        activeMode = .overlayHalo
        return cursorHaloOverlay.show()
    }

    @discardableResult
    func deactivateTakeoverCursor() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard activeTakeoverCount > 0 else {
            return true
        }

        activeTakeoverCount -= 1
        guard activeTakeoverCount == 0 else {
            return true
        }

        defer {
            originalCursorSize = nil
            activeMode = nil
        }

        switch activeMode {
        case .overlayHalo:
            return cursorHaloOverlay.hide()
        case .systemCursorSize:
            guard let originalCursorSize else {
                return true
            }
            return writeCursorSize(originalCursorSize)
        case .none:
            return true
        }
    }

    private func readCursorSize() -> Double? {
        guard let value = CFPreferencesCopyAppValue(cursorSizeKey, preferenceDomain) else {
            return nil
        }

        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let text = value as? String {
            return Double(text)
        }
        return nil
    }

    private func writeCursorSize(_ size: Double) -> Bool {
        let value = NSNumber(value: size)
        CFPreferencesSetAppValue(cursorSizeKey, value, preferenceDomain)
        return CFPreferencesAppSynchronize(preferenceDomain)
    }
}

private final class CursorHaloOverlay {
    private final class HaloView: NSView {
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard let context = NSGraphicsContext.current?.cgContext else { return }

            let outerInset: CGFloat = 6
            let innerInset: CGFloat = 28
            let outerRect = bounds.insetBy(dx: outerInset, dy: outerInset)
            let innerRect = bounds.insetBy(dx: innerInset, dy: innerInset)

            context.setFillColor(NSColor.systemYellow.withAlphaComponent(0.16).cgColor)
            context.fillEllipse(in: outerRect)

            context.setStrokeColor(NSColor.systemYellow.withAlphaComponent(0.95).cgColor)
            context.setLineWidth(6)
            context.strokeEllipse(in: outerRect)

            context.setStrokeColor(NSColor.black.withAlphaComponent(0.45).cgColor)
            context.setLineWidth(3)
            context.strokeEllipse(in: innerRect)
        }
    }

    private let haloSize = NSSize(width: 120, height: 120)
    private var window: NSWindow?
    private var timer: Timer?

    @discardableResult
    func show() -> Bool {
        if Thread.isMainThread {
            showOnMain()
            return window != nil
        }

        var success = false
        DispatchQueue.main.sync {
            showOnMain()
            success = window != nil
        }
        return success
    }

    @discardableResult
    func hide() -> Bool {
        if Thread.isMainThread {
            hideOnMain()
            return true
        }

        DispatchQueue.main.sync {
            hideOnMain()
        }
        return true
    }

    private func showOnMain() {
        if window == nil {
            let frame = frameCentered(at: NSEvent.mouseLocation)
            let newWindow = NSWindow(
                contentRect: frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.hasShadow = false
            newWindow.ignoresMouseEvents = true
            newWindow.level = .statusBar
            newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            newWindow.hidesOnDeactivate = false
            newWindow.isReleasedWhenClosed = false
            newWindow.contentView = HaloView(frame: NSRect(origin: .zero, size: haloSize))
            window = newWindow
        }

        window?.orderFrontRegardless()
        updatePosition()
        startTimerIfNeeded()
    }

    private func hideOnMain() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window = nil
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.updatePosition()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func updatePosition() {
        guard let window else { return }
        window.setFrame(frameCentered(at: NSEvent.mouseLocation), display: true)
    }

    private func frameCentered(at point: NSPoint) -> NSRect {
        NSRect(
            x: point.x - haloSize.width / 2.0,
            y: point.y - haloSize.height / 2.0,
            width: haloSize.width,
            height: haloSize.height
        )
    }
}
