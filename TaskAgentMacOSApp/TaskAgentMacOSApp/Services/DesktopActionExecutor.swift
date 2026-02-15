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
    func openApp(named appName: String) throws {
        guard let appURL = resolveAppURL(named: appName) else {
            throw DesktopActionExecutorError.appOpenFailed(appName)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        var launchError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            launchError = error
            semaphore.signal()
        }
        semaphore.wait()
        if launchError != nil {
            throw DesktopActionExecutorError.appOpenFailed(appName)
        }
    }

    func openURL(_ url: URL) throws {
        guard NSWorkspace.shared.open(url) else {
            throw DesktopActionExecutorError.invalidURL
        }
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
}

