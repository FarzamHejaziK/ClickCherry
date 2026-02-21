import Foundation
import AppKit
import ApplicationServices

enum DesktopActionIntent: Equatable {
    case openApp(String)
    case openURL(URL)
    case keyShortcut(key: String, command: Bool, option: Bool, control: Bool, shift: Bool)
    case typeText(String)
    case click(x: Int, y: Int)
    case moveMouse(x: Int, y: Int)
    case rightClick(x: Int, y: Int)
    case scroll(deltaX: Int, deltaY: Int)
}

protocol DesktopActionExecutor {
    func openApp(named appName: String) throws
    func openURL(_ url: URL) throws
    func sendShortcut(key: String, command: Bool, option: Bool, control: Bool, shift: Bool) throws
    func typeText(_ text: String) throws
    func click(x: Int, y: Int) throws
    func moveMouse(x: Int, y: Int) throws
    func rightClick(x: Int, y: Int) throws
    func scroll(deltaX: Int, deltaY: Int) throws
}

enum DesktopActionExecutorError: Error, Equatable, LocalizedError {
    case invalidURL
    case appOpenFailed(String)
    case clickInjectionFailed
    case mouseMoveInjectionFailed
    case rightClickInjectionFailed
    case scrollInjectionFailed
    case keyInjectionFailed
    case unsupportedKey(String)
    case typeInjectionFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Failed to open URL."
        case .appOpenFailed(let name):
            return "Failed to open app '\(name)'."
        case .clickInjectionFailed:
            return "Failed to inject click event (check Accessibility permission)."
        case .mouseMoveInjectionFailed:
            return "Failed to inject mouse move event (check Accessibility permission)."
        case .rightClickInjectionFailed:
            return "Failed to inject right click event (check Accessibility permission)."
        case .scrollInjectionFailed:
            return "Failed to inject scroll event (check Accessibility permission)."
        case .keyInjectionFailed:
            return "Failed to inject key shortcut (check Accessibility permission)."
        case .unsupportedKey(let key):
            return "Unsupported key '\(key)'."
        case .typeInjectionFailed:
            return "Failed to inject typed text (check Accessibility permission)."
        }
    }
}

struct SystemDesktopActionExecutor: DesktopActionExecutor {
    private static let windowRelocationAttempts = 12
    private static let windowRelocationIntervalSeconds = 0.15
    private static let windowRelocationEdgeInset: CGFloat = 24

    func openApp(named appName: String) throws {
        guard let appURL = resolveAppURL(named: appName) else {
            throw DesktopActionExecutorError.appOpenFailed(appName)
        }
        let targetScreenFrame = targetDisplayVisibleFrameAtPointer()
        let targetBundleIdentifier = Bundle(url: appURL)?.bundleIdentifier
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        var openedApplication: NSRunningApplication?
        var launchError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
            openedApplication = app
            launchError = error
            semaphore.signal()
        }
        semaphore.wait()
        if launchError != nil {
            throw DesktopActionExecutorError.appOpenFailed(appName)
        }

        guard let targetScreenFrame else {
            return
        }

        if let app = openedApplication ?? runningApplication(bundleIdentifier: targetBundleIdentifier) {
            relocateFrontWindowIfPossible(for: app, targetVisibleFrame: targetScreenFrame)
        }
    }

    func openURL(_ url: URL) throws {
        let targetScreenFrame = targetDisplayVisibleFrameAtPointer()
        guard NSWorkspace.shared.open(url) else {
            throw DesktopActionExecutorError.invalidURL
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        guard let targetScreenFrame,
              let frontmostApp = waitForFrontmostRegularApp(excluding: currentPID) else {
            return
        }
        relocateFrontWindowIfPossible(for: frontmostApp, targetVisibleFrame: targetScreenFrame)
    }

    func sendShortcut(key: String, command: Bool, option: Bool, control: Bool, shift: Bool) throws {
        guard let code = keyCode(for: key) else {
            throw DesktopActionExecutorError.unsupportedKey(key)
        }

        let flags = cgEventFlags(command: command, option: option, control: control, shift: shift)
        try postKey(code: code, flags: flags)
    }

    func typeText(_ text: String) throws {
        // Clipboard-paste is significantly more reliable for macOS system UI targets (notably Spotlight),
        // while still avoiding "System Events" automation permissions.
        try pasteTextViaClipboard(text)
    }

    func click(x: Int, y: Int) throws {
        let point = CGPoint(x: x, y: y)
        guard
            let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left),
            let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
            let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        else {
            throw DesktopActionExecutorError.clickInjectionFailed
        }
        markSynthetic(move)
        markSynthetic(down)
        markSynthetic(up)
        move.post(tap: .cghidEventTap)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    func moveMouse(x: Int, y: Int) throws {
        let point = CGPoint(x: x, y: y)
        guard let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else {
            throw DesktopActionExecutorError.mouseMoveInjectionFailed
        }
        markSynthetic(move)
        move.post(tap: .cghidEventTap)
    }

    func rightClick(x: Int, y: Int) throws {
        let point = CGPoint(x: x, y: y)
        guard
            let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .right),
            let down = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right),
            let up = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right)
        else {
            throw DesktopActionExecutorError.rightClickInjectionFailed
        }
        markSynthetic(move)
        markSynthetic(down)
        markSynthetic(up)
        move.post(tap: .cghidEventTap)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    func scroll(deltaX: Int, deltaY: Int) throws {
        let dx = Int32(clamping: deltaX)
        let dy = Int32(clamping: deltaY)
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: dy,
            wheel2: dx,
            wheel3: 0
        ) else {
            throw DesktopActionExecutorError.scrollInjectionFailed
        }
        markSynthetic(event)
        event.post(tap: .cghidEventTap)
    }

    private func cgEventFlags(command: Bool, option: Bool, control: Bool, shift: Bool) -> CGEventFlags {
        var flags: CGEventFlags = []
        if command { flags.insert(.maskCommand) }
        if option { flags.insert(.maskAlternate) }
        if control { flags.insert(.maskControl) }
        if shift { flags.insert(.maskShift) }
        return flags
    }

    private func postKey(code: CGKeyCode, flags: CGEventFlags) throws {
        guard
            let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
            let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
        else {
            throw DesktopActionExecutorError.keyInjectionFailed
        }
        markSynthetic(down)
        markSynthetic(up)
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func markSynthetic(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: DesktopEventSignature.syntheticEventUserData)
    }

    private struct PasteboardSnapshot {
        struct Item {
            var dataByType: [NSPasteboard.PasteboardType: Data]
        }

        var items: [Item]
        var didTruncate: Bool

        static func capture(from pasteboard: NSPasteboard, maxBytes: Int = 4 * 1024 * 1024) -> PasteboardSnapshot {
            let pbItems = pasteboard.pasteboardItems ?? []
            var captured: [Item] = []
            var totalBytes = 0
            var truncated = false

            for pbItem in pbItems {
                var dataByType: [NSPasteboard.PasteboardType: Data] = [:]

                if let data = pbItem.data(forType: .string) {
                    if totalBytes + data.count <= maxBytes {
                        dataByType[.string] = data
                        totalBytes += data.count
                    } else {
                        truncated = true
                    }
                }

                if !truncated {
                    for type in pbItem.types where type != .string {
                        guard let data = pbItem.data(forType: type) else { continue }
                        if totalBytes + data.count > maxBytes {
                            truncated = true
                            break
                        }
                        dataByType[type] = data
                        totalBytes += data.count
                    }
                }

                captured.append(Item(dataByType: dataByType))

                if truncated {
                    break
                }
            }

            return PasteboardSnapshot(items: captured, didTruncate: truncated)
        }

        func restore(to pasteboard: NSPasteboard) {
            pasteboard.clearContents()
            guard !items.isEmpty else { return }

            let objects: [NSPasteboardItem] = items.compactMap { item in
                guard !item.dataByType.isEmpty else { return nil }
                let pbItem = NSPasteboardItem()
                for (type, data) in item.dataByType {
                    pbItem.setData(data, forType: type)
                }
                return pbItem
            }
            _ = pasteboard.writeObjects(objects)
        }
    }

    private func pasteTextViaClipboard(_ text: String) throws {
        guard let code = keyCode(for: "v") else {
            throw DesktopActionExecutorError.typeInjectionFailed
        }

        let pasteboard = NSPasteboard.general
        let snapshot = runOnMain {
            PasteboardSnapshot.capture(from: pasteboard)
        }

        defer {
            runOnMain {
                snapshot.restore(to: pasteboard)
            }
        }

        runOnMain {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }

        Thread.sleep(forTimeInterval: 0.02)

        let flags = cgEventFlags(command: true, option: false, control: false, shift: false)
        try postKey(code: code, flags: flags)

        Thread.sleep(forTimeInterval: 0.30)
    }

    private func runOnMain<T>(_ work: () -> T) -> T {
        if Thread.isMainThread {
            return work()
        }
        var output: T?
        DispatchQueue.main.sync {
            output = work()
        }
        return output!
    }

    private func keyCode(for key: String) -> CGKeyCode? {
        if key == " " {
            return 49
        }

        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "space" || normalized == "spacebar" {
            return 49
        }
        if normalized == "return" || normalized == "enter" {
            return 36
        }
        if normalized == "tab" {
            return 48
        }
        if normalized == "escape" || normalized == "esc" {
            return 53
        }
        if normalized == "left" {
            return 123
        }
        if normalized == "right" {
            return 124
        }
        if normalized == "down" {
            return 125
        }
        if normalized == "up" {
            return 126
        }

        if normalized.count == 1, let scalar = normalized.unicodeScalars.first {
            switch scalar.value {
            case 97: return 0   // a
            case 98: return 11  // b
            case 99: return 8   // c
            case 100: return 2  // d
            case 101: return 14 // e
            case 102: return 3  // f
            case 103: return 5  // g
            case 104: return 4  // h
            case 105: return 34 // i
            case 106: return 38 // j
            case 107: return 40 // k
            case 108: return 37 // l
            case 109: return 46 // m
            case 110: return 45 // n
            case 111: return 31 // o
            case 112: return 35 // p
            case 113: return 12 // q
            case 114: return 15 // r
            case 115: return 1  // s
            case 116: return 17 // t
            case 117: return 32 // u
            case 118: return 9  // v
            case 119: return 13 // w
            case 120: return 7  // x
            case 121: return 16 // y
            case 122: return 6  // z
            case 48: return 29  // 0
            case 49: return 18  // 1
            case 50: return 19  // 2
            case 51: return 20  // 3
            case 52: return 21  // 4
            case 53: return 23  // 5
            case 54: return 22  // 6
            case 55: return 26  // 7
            case 56: return 28  // 8
            case 57: return 25  // 9
            case 44: return 43  // ,
            case 46: return 47  // .
            case 47: return 44  // /
            case 59: return 41  // ;
            case 39: return 39  // '
            case 91: return 33  // [
            case 93: return 30  // ]
            case 92: return 42  // \\
            case 45: return 27  // -
            case 61: return 24  // =
            case 96: return 50  // `
            default:
                return nil
            }
        }

        return nil
    }

    private func resolveAppURL(named appName: String) -> URL? {
        let normalized = appName.hasSuffix(".app") ? appName : "\(appName).app"
        let homeApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        let searchRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            homeApplications
        ]
        for root in searchRoots {
            let candidate = root.appendingPathComponent(normalized, isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private func targetDisplayVisibleFrameAtPointer() -> CGRect? {
        let pointer = CGEvent(source: nil)?.location ?? runOnMain { NSEvent.mouseLocation }

        return runOnMain {
            if let screen = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(pointer) }) {
                return screen.visibleFrame
            }
            if let main = NSScreen.main {
                return main.visibleFrame
            }
            return NSScreen.screens.first?.visibleFrame
        }
    }

    private func runningApplication(bundleIdentifier: String?) -> NSRunningApplication? {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
            return nil
        }

        return runOnMain {
            NSWorkspace.shared.runningApplications.first(where: { app in
                app.bundleIdentifier == bundleIdentifier && app.activationPolicy == .regular
            })
        }
    }

    private func waitForFrontmostRegularApp(excluding excludedPID: pid_t? = nil) -> NSRunningApplication? {
        for attempt in 0..<Self.windowRelocationAttempts {
            if let app = runOnMain({ NSWorkspace.shared.frontmostApplication }),
               app.activationPolicy == .regular,
               app.processIdentifier != excludedPID {
                return app
            }

            if attempt < Self.windowRelocationAttempts - 1 {
                Thread.sleep(forTimeInterval: Self.windowRelocationIntervalSeconds)
            }
        }

        return nil
    }

    private func relocateFrontWindowIfPossible(for application: NSRunningApplication, targetVisibleFrame: CGRect) {
        guard AXIsProcessTrusted() else {
            return
        }

        _ = application.activate(options: [.activateAllWindows])
        let appElement = AXUIElementCreateApplication(application.processIdentifier)

        for attempt in 0..<Self.windowRelocationAttempts {
            if moveFrontWindow(of: appElement, into: targetVisibleFrame) {
                return
            }

            if attempt < Self.windowRelocationAttempts - 1 {
                Thread.sleep(forTimeInterval: Self.windowRelocationIntervalSeconds)
            }
        }
    }

    private func moveFrontWindow(of appElement: AXUIElement, into targetVisibleFrame: CGRect) -> Bool {
        guard let window = focusedWindow(of: appElement) ?? firstWindow(of: appElement) else {
            return false
        }

        _ = setAXBool(window, attribute: kAXMinimizedAttribute as CFString, value: false)

        let windowSize = windowSize(of: window) ?? CGSize(
            width: max(420, targetVisibleFrame.width * 0.72),
            height: max(320, targetVisibleFrame.height * 0.72)
        )
        let destination = centeredWindowOrigin(for: windowSize, in: targetVisibleFrame)
        guard setAXPosition(window, destination) else {
            return false
        }

        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        _ = setAXBool(window, attribute: kAXMainAttribute as CFString, value: true)
        _ = setAXBool(window, attribute: kAXFocusedAttribute as CFString, value: true)
        return true
    }

    private func focusedWindow(of appElement: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success else {
            return nil
        }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func firstWindow(of appElement: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == CFArrayGetTypeID() else {
            return nil
        }

        let windowCandidates = unsafeBitCast(value, to: NSArray.self)
        for candidate in windowCandidates {
            let cfCandidate = candidate as CFTypeRef
            guard CFGetTypeID(cfCandidate) == AXUIElementGetTypeID() else {
                continue
            }
            return unsafeBitCast(cfCandidate, to: AXUIElement.self)
        }

        return nil
    }

    private func windowSize(of window: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value) == .success,
              let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        let typedValue = unsafeBitCast(axValue, to: AXValue.self)
        guard AXValueGetType(typedValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(typedValue, .cgSize, &size) else {
            return nil
        }

        return size
    }

    private func setAXPosition(_ window: AXUIElement, _ point: CGPoint) -> Bool {
        var target = point
        guard let value = AXValueCreate(.cgPoint, &target) else {
            return false
        }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success
    }

    private func setAXBool(_ element: AXUIElement, attribute: CFString, value: Bool) -> Bool {
        let boolValue: CFBoolean = value ? kCFBooleanTrue : kCFBooleanFalse
        return AXUIElementSetAttributeValue(element, attribute, boolValue) == .success
    }

    private func centeredWindowOrigin(for windowSize: CGSize, in targetVisibleFrame: CGRect) -> CGPoint {
        let inset = Self.windowRelocationEdgeInset
        let minX = targetVisibleFrame.minX + inset
        let minY = targetVisibleFrame.minY + inset
        let maxX = targetVisibleFrame.maxX - windowSize.width - inset
        let maxY = targetVisibleFrame.maxY - windowSize.height - inset

        var centeredX = targetVisibleFrame.midX - (windowSize.width / 2)
        var centeredY = targetVisibleFrame.midY - (windowSize.height / 2)

        if maxX >= minX {
            centeredX = min(max(centeredX, minX), maxX)
        } else {
            centeredX = minX
        }

        if maxY >= minY {
            centeredY = min(max(centeredY, minY), maxY)
        } else {
            centeredY = minY
        }

        return CGPoint(x: centeredX, y: centeredY)
    }
}
