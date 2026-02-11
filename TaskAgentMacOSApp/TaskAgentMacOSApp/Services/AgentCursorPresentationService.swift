import Foundation

protocol AgentCursorPresentationService {
    @discardableResult
    func activateTakeoverCursor() -> Bool

    @discardableResult
    func deactivateTakeoverCursor() -> Bool
}

final class AccessibilityAgentCursorPresentationService: AgentCursorPresentationService {
    private let lock = NSLock()
    private var activeTakeoverCount: Int = 0

    @discardableResult
    func activateTakeoverCursor() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        activeTakeoverCount += 1
        // Keep the system cursor unchanged during takeover.
        return true
    }

    @discardableResult
    func deactivateTakeoverCursor() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if activeTakeoverCount > 0 {
            activeTakeoverCount -= 1
        }
        return true
    }
}
