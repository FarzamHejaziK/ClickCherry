import Foundation
import AppKit
import ApplicationServices
import Darwin
import ImageIO
import UniformTypeIdentifiers

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
    case appleScriptFailed(String)
    case clickInjectionFailed
    case mouseMoveInjectionFailed
    case rightClickInjectionFailed
    case scrollInjectionFailed
    case keyInjectionFailed
    case typeInjectionFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Failed to open URL."
        case .appOpenFailed(let name):
            return "Failed to open app '\(name)'."
        case .appleScriptFailed(let message):
            return "Automation (AppleScript) failed: \(message)"
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
        // Prefer CGEvent-based injection: avoids "System Events" automation permissions.
        if let code = keyCode(for: key) {
            let flags = cgEventFlags(command: command, option: option, control: control, shift: shift)
            try postKey(code: code, flags: flags)
            return
        }

        // Fallback to AppleScript for unrecognized keys.
        var modifiers: [String] = []
        if command { modifiers.append("command down") }
        if option { modifiers.append("option down") }
        if control { modifiers.append("control down") }
        if shift { modifiers.append("shift down") }

        let keyLiteral = key == "return" ? "return" : "\"\(key)\""
        let usingClause = modifiers.isEmpty ? "" : " using {\(modifiers.joined(separator: ", "))}"
        let script = """
        tell application "System Events"
            keystroke \(keyLiteral)\(usingClause)
        end tell
        """
        try runAppleScript(script)
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

    private func postUnicode(_ text: String) throws {
        // Some targets (including macOS system UI) can behave inconsistently when we attach
        // an entire string to one keyDown/keyUp pair. Emit per-scalar unicode events instead.
        for scalar in text.unicodeScalars {
            let utf16 = Array(String(scalar).utf16)
            guard !utf16.isEmpty else { continue }
            guard
                let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            else {
                throw DesktopActionExecutorError.typeInjectionFailed
            }
            markSynthetic(down)
            markSynthetic(up)

            utf16.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                // KeyUp does not need the unicode payload; keep it empty to avoid duplicate delivery.
                // (Some apps treat keyUp unicode content oddly.)
            }

            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
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

                // Always try to capture plain string first.
                if let data = pbItem.data(forType: .string) {
                    if totalBytes + data.count <= maxBytes {
                        dataByType[.string] = data
                        totalBytes += data.count
                    } else {
                        truncated = true
                    }
                }

                // Best-effort capture of other types, bounded by maxBytes.
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
            // Should never happen (we map ASCII letters), but keep an explicit failure mode.
            throw DesktopActionExecutorError.typeInjectionFailed
        }

        let pasteboard = NSPasteboard.general
        let snapshot = runOnMain {
            PasteboardSnapshot.capture(from: pasteboard)
        }

        // Ensure we restore the user's clipboard even if paste fails.
        defer {
            runOnMain {
                snapshot.restore(to: pasteboard)
            }
        }

        runOnMain {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }

        // Give the pasteboard a moment to update before sending cmd+v.
        Thread.sleep(forTimeInterval: 0.02)

        let flags = cgEventFlags(command: true, option: false, control: false, shift: false)
        try postKey(code: code, flags: flags)

        // Allow the target app to read from the pasteboard before we restore it.
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
        // output is always set because `DispatchQueue.main.sync` is synchronous.
        return output!
    }

    private func keyCode(for key: String) -> CGKeyCode? {
        // Important: don't trim whitespace before checking for the space key, otherwise " " becomes "".
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

        // Single ASCII character keys (letters/numbers and common punctuation).
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

    private func runAppleScript(_ source: String) throws {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        script?.executeAndReturnError(&error)
        if let error,
           let message = error[NSAppleScript.errorMessage] as? String {
            throw DesktopActionExecutorError.appleScriptFailed(message)
        }
    }
}

enum AnthropicExecutionPlannerError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case failedToReadAPIKey
    case failedToLoadPrompt(String)
    case invalidResponse
    case requestFailed(String)
    case screenshotCaptureFailed
    case screenshotTooLarge(Int)
    case invalidToolLoopResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Anthropic API key is not configured. Save one in Provider API Keys."
        case .failedToReadAPIKey:
            return "Failed to read Anthropic API key from secure storage."
        case .failedToLoadPrompt(let promptName):
            return "Failed to load prompt '\(promptName)' from prompt catalog."
        case .invalidResponse:
            return "Anthropic response format was invalid."
        case .requestFailed(let reason):
            return "Anthropic task execution request failed: \(reason)"
        case .screenshotCaptureFailed:
            return "Failed to capture current desktop screenshot."
        case .screenshotTooLarge(let maxBytes):
            return "Captured desktop screenshot is too large for Anthropic (base64 image payload must be <= \(maxBytes) bytes)."
        case .invalidToolLoopResponse:
            return "Anthropic tool-loop response format was invalid."
        }
    }
}

struct AnthropicCapturedScreenshot {
    var width: Int
    var height: Int
    // Screenshot pixel dimensions from the capture output (often 2x logical size on Retina).
    var captureWidthPx: Int
    var captureHeightPx: Int
    // Coordinate space used for CGEvent injection. On modern macOS this matches CGDisplayBounds (logical pixels/points),
    // which is typically half the captured screenshot pixel dimensions on Retina displays.
    var coordinateSpaceWidthPx: Int
    var coordinateSpaceHeightPx: Int
    var mediaType: String
    var base64Data: String
    var byteCount: Int
}

final class AnthropicComputerUseRunner: LLMExecutionToolLoopRunner {
    struct TransportRetryPolicy: Equatable {
        var maxAttempts: Int
        var baseDelaySeconds: Double
        var maxDelaySeconds: Double

        static let `default` = TransportRetryPolicy(
            maxAttempts: 5,
            baseDelaySeconds: 0.5,
            maxDelaySeconds: 6.0
        )
    }

    private struct ToolExecutionResult {
        var toolUseId: String
        var contentBlocks: [AnthropicToolResultContent]
        var isError: Bool
        var stepDescription: String?
        var generatedQuestions: [String]
    }

    private struct CompletionResult {
        var outcome: AutomationRunOutcome
        var summary: String?
        var questions: [String]
        var errorMessage: String?
    }

    private let apiKeyStore: any APIKeyStore
    private let promptCatalog: PromptCatalogService
    private let promptName: String
    private let session: URLSession
    private let transportRetryPolicy: TransportRetryPolicy
    private let sleepNanoseconds: @Sendable (UInt64) async -> Void
    private let screenshotProvider: () throws -> AnthropicCapturedScreenshot
    private let cursorPositionProvider: () -> (x: Int, y: Int)?
    private let screenshotLogSink: ((LLMScreenshotLogEntry) -> Void)?
    private let callLogSink: ((LLMCallLogEntry) -> Void)?
    private let traceSink: ((ExecutionTraceEntry) -> Void)?
    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()
    private var coordinateScaleX: Double = 1.0
    private var coordinateScaleY: Double = 1.0
    private var toolDisplayWidthPx: Int = 0
    private var toolDisplayHeightPx: Int = 0
    private var coordinateSpaceWidthPx: Int = 0
    private var coordinateSpaceHeightPx: Int = 0

    init(
        apiKeyStore: any APIKeyStore,
        promptCatalog: PromptCatalogService = PromptCatalogService(),
        promptName: String = "execution_agent",
        callLogSink: ((LLMCallLogEntry) -> Void)? = nil,
        screenshotLogSink: ((LLMScreenshotLogEntry) -> Void)? = nil,
        traceSink: ((ExecutionTraceEntry) -> Void)? = nil,
        session: URLSession = .shared,
        transportRetryPolicy: TransportRetryPolicy = .default,
        sleepNanoseconds: @escaping @Sendable (UInt64) async -> Void = { nanos in
            try? await Task.sleep(nanoseconds: nanos)
        },
        beforeScreenshotCapture: (@Sendable () -> Void)? = nil,
        afterScreenshotCapture: (@Sendable () -> Void)? = nil,
        screenshotProvider: @escaping () throws -> AnthropicCapturedScreenshot = AnthropicComputerUseRunner.captureMainDisplayScreenshot,
        cursorPositionProvider: @escaping () -> (x: Int, y: Int)? = AnthropicComputerUseRunner.currentCursorPosition
    ) {
        self.apiKeyStore = apiKeyStore
        self.promptCatalog = promptCatalog
        self.promptName = promptName
        self.callLogSink = callLogSink
        self.traceSink = traceSink
        self.session = session
        self.transportRetryPolicy = transportRetryPolicy
        self.sleepNanoseconds = sleepNanoseconds
        self.screenshotLogSink = screenshotLogSink
        self.screenshotProvider = {
            beforeScreenshotCapture?()
            defer { afterScreenshotCapture?() }
            return try screenshotProvider()
        }
        self.cursorPositionProvider = cursorPositionProvider
    }

    func runToolLoop(taskMarkdown: String, executor: any DesktopActionExecutor) async throws -> AutomationRunResult {
        let promptTemplate = try loadPromptTemplate()
        let apiKey = try resolveAPIKey()

        recordTrace(kind: .info, "Execution started (model=\(promptTemplate.config.llm), tool=computer_20251124).")

        let initialScreenshot: AnthropicCapturedScreenshot
        do {
            initialScreenshot = try captureScreenshotForLLM(source: .initialPromptImage)
        } catch {
            throw AnthropicExecutionPlannerError.screenshotCaptureFailed
        }

        // If we downscale screenshots to fit the Anthropic 5 MB limit, map tool coordinates back to physical pixels.
        toolDisplayWidthPx = initialScreenshot.width
        toolDisplayHeightPx = initialScreenshot.height
        coordinateSpaceWidthPx = initialScreenshot.coordinateSpaceWidthPx
        coordinateSpaceHeightPx = initialScreenshot.coordinateSpaceHeightPx
        if initialScreenshot.width > 0, initialScreenshot.height > 0 {
            coordinateScaleX = Double(initialScreenshot.coordinateSpaceWidthPx) / Double(initialScreenshot.width)
            coordinateScaleY = Double(initialScreenshot.coordinateSpaceHeightPx) / Double(initialScreenshot.height)
        } else {
            coordinateScaleX = 1.0
            coordinateScaleY = 1.0
        }

        recordTrace(
            kind: .info,
            "Captured initial screenshot (\(initialScreenshot.width)x\(initialScreenshot.height), \(initialScreenshot.mediaType), raw=\(initialScreenshot.byteCount) bytes, base64=\(initialScreenshot.base64Data.utf8.count) bytes; capture=\(initialScreenshot.captureWidthPx)x\(initialScreenshot.captureHeightPx) coordSpace=\(initialScreenshot.coordinateSpaceWidthPx)x\(initialScreenshot.coordinateSpaceHeightPx))."
        )

        let tools: [AnthropicToolSpec] = [
            .computer(
                AnthropicComputerToolDefinition(
                    type: "computer_20251124",
                    name: "computer",
                    displayWidthPx: initialScreenshot.width,
                    displayHeightPx: initialScreenshot.height,
                    displayNumber: 1
                )
            ),
            .function(
                AnthropicFunctionToolDefinition(
                    name: "terminal_exec",
                    description: "Execute a terminal command and return stdout/stderr/exit_code. Use this for command-line tasks and reliable app launching.",
                    inputSchema: .object(
                        properties: [
                            "executable": .string(description: "Executable name (resolved from PATH) or absolute path."),
                            "args": .array(items: .string(description: "Argument string."), description: "Argument list."),
                            "timeout_seconds": .number(description: "Optional timeout in seconds (default 30).")
                        ],
                        required: ["executable"],
                        additionalProperties: false
                    )
                )
            )
        ]

        var messages: [AnthropicConversationMessage] = [
            .init(
                role: "user",
                content: [
                    .text(renderPrompt(promptTemplate.prompt, taskMarkdown: taskMarkdown)),
                    .image(initialScreenshot)
                ]
            )
        ]

        var executedSteps: [String] = []
        var generatedQuestions: [String] = []

        do {
            for turn in 1...200 {
                try Task.checkCancellation()

                let compacted = compactMessagesKeepingLatestImage(messages)
                if compacted.removedImageCount > 0 {
                    recordTrace(
                        kind: .info,
                        "Compacted message history by removing \(compacted.removedImageCount) old screenshot image block(s); keeping only the latest image."
                    )
                }

                let payload = try await sendMessagesRequest(
                    AnthropicMessagesRequest(
                        model: promptTemplate.config.llm,
                        maxTokens: 2048,
                        system: "",
                        messages: compacted.messages,
                        tools: tools
                    ),
                    apiKey: apiKey,
                    includeComputerUseBetaHeader: true
                )

                guard !payload.content.isEmpty else {
                    throw AnthropicExecutionPlannerError.invalidToolLoopResponse
                }

                recordTrace(kind: .llmResponse, summarizeAssistantResponse(turn: turn, content: payload.content))

                messages.append(.init(role: "assistant", content: payload.content))

                let toolUses = payload.content.filter { $0.type == "tool_use" }
                if toolUses.isEmpty {
                    let completionText = payload.content
                        .filter { $0.type == "text" }
                        .compactMap(\.text)
                        .joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let completion = parseCompletion(from: completionText)

                    recordTrace(
                        kind: .completion,
                        "Completion: status=\(completion.outcome) questions=\(completion.questions.count) summary=\(completion.summary == nil ? "none" : "present")"
                    )

                    return AutomationRunResult(
                        outcome: completion.outcome,
                        executedSteps: executedSteps,
                        generatedQuestions: dedupe(generatedQuestions + completion.questions),
                        errorMessage: completion.errorMessage,
                        llmSummary: completion.summary
                    )
                }

                var toolResults: [AnthropicMessageContent] = []
                for toolUse in toolUses {
                    try Task.checkCancellation()
                    guard let toolUseId = toolUse.id, !toolUseId.isEmpty else {
                        throw AnthropicExecutionPlannerError.invalidToolLoopResponse
                    }

                    recordTrace(kind: .toolUse, summarizeToolUse(toolUse))

                    let result = try await executeToolUse(
                        toolUseId: toolUseId,
                        toolName: toolUse.name,
                        input: toolUse.input,
                        executor: executor
                    )

                    if let stepDescription = result.stepDescription {
                        executedSteps.append(stepDescription)
                        recordTrace(kind: .localAction, stepDescription)
                    } else if result.isError {
                        let failureText = result.contentBlocks.compactMap(\.text).first ?? "Tool execution failed."
                        recordTrace(kind: .error, failureText)
                    }
                    generatedQuestions.append(contentsOf: result.generatedQuestions)

                    toolResults.append(
                        .toolResult(
                            toolUseId: result.toolUseId,
                            content: result.contentBlocks.isEmpty ? [.text("Done")] : result.contentBlocks,
                            isError: result.isError
                        )
                    )
                }

                messages.append(.init(role: "user", content: toolResults))
            }
        } catch is CancellationError {
            recordTrace(kind: .cancelled, "Cancelled by user.")
            return AutomationRunResult(
                outcome: .cancelled,
                executedSteps: executedSteps,
                generatedQuestions: [],
                errorMessage: nil,
                llmSummary: "Cancelled by user."
            )
        }

        return AutomationRunResult(
            outcome: .needsClarification,
            executedSteps: executedSteps,
            generatedQuestions: dedupe(generatedQuestions + ["Execution loop exceeded safe iteration limit. How should I proceed?"]),
            errorMessage: "Execution loop did not converge.",
            llmSummary: nil
        )
    }

    private func sendMessagesRequest(
        _ body: AnthropicMessagesRequest,
        apiKey: String,
        includeComputerUseBetaHeader: Bool
    ) async throws -> AnthropicMessagesResponse {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if includeComputerUseBetaHeader {
            request.setValue("computer-use-2025-11-24", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try jsonEncoder.encode(body)

        let bytesSent = request.httpBody?.count
        let urlString = request.url?.absoluteString ?? "unknown"

        let pair: (data: Data, response: URLResponse, attempt: Int, attemptStartedAt: Date)
        let response: HTTPURLResponse
        let data: Data
        let attempt: Int
        let attemptStartedAt: Date
        do {
            pair = try await dataWithRetry(for: request)
            guard let http = pair.response as? HTTPURLResponse else {
                recordCall(
                    startedAt: pair.attemptStartedAt,
                    finishedAt: Date(),
                    attempt: pair.attempt,
                    url: urlString,
                    httpStatus: nil,
                    requestId: nil,
                    bytesSent: bytesSent,
                    bytesReceived: pair.data.count,
                    outcome: .failure,
                    message: "Non-HTTP response."
                )
                throw AnthropicExecutionPlannerError.invalidResponse
            }
            response = http
            data = pair.data
            attempt = pair.attempt
            attemptStartedAt = pair.attemptStartedAt
        } catch let error as AnthropicExecutionPlannerError {
            throw error
        } catch {
            if isCancellation(error) {
                throw CancellationError()
            }
            throw AnthropicExecutionPlannerError.requestFailed(describeTransportError(error))
        }

        guard (200..<300).contains(response.statusCode) else {
            let message = serverMessage(from: data, statusCode: response.statusCode)
            recordCall(
                startedAt: attemptStartedAt,
                finishedAt: Date(),
                attempt: attempt,
                url: urlString,
                httpStatus: response.statusCode,
                requestId: headerValue(response, name: "request-id"),
                bytesSent: bytesSent,
                bytesReceived: data.count,
                outcome: .failure,
                message: message
            )
            throw AnthropicExecutionPlannerError.requestFailed(message)
        }

        guard let payload = try? jsonDecoder.decode(AnthropicMessagesResponse.self, from: data) else {
            recordCall(
                startedAt: attemptStartedAt,
                finishedAt: Date(),
                attempt: attempt,
                url: urlString,
                httpStatus: response.statusCode,
                requestId: headerValue(response, name: "request-id"),
                bytesSent: bytesSent,
                bytesReceived: data.count,
                outcome: .failure,
                message: "Failed to decode Anthropic response JSON."
            )
            throw AnthropicExecutionPlannerError.invalidResponse
        }

        recordCall(
            startedAt: attemptStartedAt,
            finishedAt: Date(),
            attempt: attempt,
            url: urlString,
            httpStatus: response.statusCode,
            requestId: headerValue(response, name: "request-id"),
            bytesSent: bytesSent,
            bytesReceived: data.count,
            outcome: .success,
            message: nil
        )
        return payload
    }

    private func dataWithRetry(for request: URLRequest) async throws -> (data: Data, response: URLResponse, attempt: Int, attemptStartedAt: Date) {
        let maxAttempts = max(1, transportRetryPolicy.maxAttempts)
        for attempt in 1...maxAttempts {
            let startedAt = Date()
            do {
                let pair = try await session.data(for: request)
                return (pair.0, pair.1, attempt, startedAt)
            } catch {
                if isCancellation(error) {
                    recordCall(
                        startedAt: startedAt,
                        finishedAt: Date(),
                        attempt: attempt,
                        url: request.url?.absoluteString ?? "unknown",
                        httpStatus: nil,
                        requestId: nil,
                        bytesSent: request.httpBody?.count,
                        bytesReceived: nil,
                        outcome: .failure,
                        message: "Cancelled."
                    )
                    throw CancellationError()
                }
                recordCall(
                    startedAt: startedAt,
                    finishedAt: Date(),
                    attempt: attempt,
                    url: request.url?.absoluteString ?? "unknown",
                    httpStatus: nil,
                    requestId: nil,
                    bytesSent: request.httpBody?.count,
                    bytesReceived: nil,
                    outcome: .failure,
                    message: describeTransportError(error)
                )

                if attempt < maxAttempts, shouldRetryTransportError(error) {
                    let delaySeconds = computeRetryDelaySeconds(attempt: attempt)
                    recordTrace(
                        kind: .info,
                        "Retrying Anthropic request after transport error (attempt \(attempt + 1)/\(maxAttempts)) after \(String(format: "%.2f", delaySeconds))s."
                    )
                    await sleepNanoseconds(UInt64(max(0.0, delaySeconds) * 1_000_000_000))
                    continue
                }
                throw error
            }
        }
        // Unreachable but keeps compiler happy.
        throw URLError(.unknown)
    }

    private func computeRetryDelaySeconds(attempt: Int) -> Double {
        // attempt is 1-based and refers to the attempt that just failed.
        // We want delays like base, 2*base, 4*base, ... capped.
        let base = max(0.0, transportRetryPolicy.baseDelaySeconds)
        let maxDelay = max(0.0, transportRetryPolicy.maxDelaySeconds)
        let exponent = max(0.0, Double(attempt - 1))
        let delay = base * pow(2.0, exponent)
        return min(delay, maxDelay)
    }

    private func shouldRetryTransportError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return false
        }

        // -1200 with underlying -9820 (errSSLPeerBadRecordMac) is often transient corruption; retry usually succeeds.
        if nsError.code == URLError.secureConnectionFailed.rawValue {
            return true
        }
        if nsError.code == URLError.networkConnectionLost.rawValue {
            return true
        }
        if nsError.code == URLError.timedOut.rawValue {
            return true
        }
        if nsError.code == URLError.cannotConnectToHost.rawValue {
            return true
        }
        if nsError.code == URLError.cannotFindHost.rawValue {
            return true
        }
        if nsError.code == URLError.dnsLookupFailed.rawValue {
            return true
        }
        if nsError.code == URLError.notConnectedToInternet.rawValue {
            return true
        }

        return false
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == URLError.cancelled.rawValue
    }

    private func recordCall(
        startedAt: Date,
        finishedAt: Date,
        attempt: Int,
        url: String,
        httpStatus: Int?,
        requestId: String?,
        bytesSent: Int?,
        bytesReceived: Int?,
        outcome: LLMCallOutcome,
        message: String?
    ) {
        callLogSink?(
            LLMCallLogEntry(
                startedAt: startedAt,
                finishedAt: finishedAt,
                provider: .anthropic,
                operation: .execution,
                attempt: attempt,
                url: url,
                httpStatus: httpStatus,
                requestId: requestId,
                bytesSent: bytesSent,
                bytesReceived: bytesReceived,
                outcome: outcome,
                message: message
            )
        )
    }

    private func headerValue(_ response: HTTPURLResponse, name: String) -> String? {
        for (keyAny, valueAny) in response.allHeaderFields {
            guard let key = keyAny as? String else { continue }
            if key.lowercased() == name.lowercased() {
                if let value = valueAny as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
                return "\(valueAny)"
            }
        }
        return nil
    }

    private func describeTransportError(_ error: Error) -> String {
        // Surface exact networking error diagnostics (domain/code + underlying chain) so TLS failures
        // are actionable for debugging in the UI.
        let nsError = error as NSError
        var components: [String] = []

        components.append("\(nsError.localizedDescription) (domain=\(nsError.domain) code=\(nsError.code))")

        if let failingURL = (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL) {
            components.append("url=\(failingURL.absoluteString)")
        }

        var depth = 0
        var underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        while let underlyingError = underlying, depth < 3 {
            components.append(
                "underlying=\(underlyingError.localizedDescription) (domain=\(underlyingError.domain) code=\(underlyingError.code))"
            )
            underlying = underlyingError.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }

        if nsError.domain == NSURLErrorDomain, nsError.code == URLError.secureConnectionFailed.rawValue {
            components.append(
                "hint=TLS handshake failed (-1200). Common causes: VPN/proxy TLS inspection, captive portals, missing/blocked trust roots, or incorrect system clock."
            )
        }

        return components.joined(separator: " | ")
    }

    private func executeToolUse(
        toolUseId: String,
        toolName: String?,
        input: JSONValue?,
        executor: any DesktopActionExecutor
    ) async throws -> ToolExecutionResult {
        let resolvedToolName = (toolName ?? "computer")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if resolvedToolName == "terminal_exec" {
            return await executeTerminalExecToolUse(toolUseId: toolUseId, input: input)
        }

        guard resolvedToolName == "computer" else {
            return ToolExecutionResult(
                toolUseId: toolUseId,
                contentBlocks: [.text("Unsupported tool '\(toolName ?? "unknown")'.")],
                isError: true,
                stepDescription: nil,
                generatedQuestions: ["Model requested unsupported tool '\(toolName ?? "unknown")'. What should I do?"]
            )
        }

        guard let object = input?.objectValue else {
            return ToolExecutionResult(
                toolUseId: toolUseId,
                contentBlocks: [.text("Tool input was invalid.")],
                isError: true,
                stepDescription: nil,
                generatedQuestions: ["Execution input from model was invalid. How should I proceed?"]
            )
        }

        let action = (object["action"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !action.isEmpty else {
            return ToolExecutionResult(
                toolUseId: toolUseId,
                contentBlocks: [.text("Tool input missing 'action'.")],
                isError: true,
                stepDescription: nil,
                generatedQuestions: ["Model omitted the requested action. What should I do?"]
            )
        }

        do {
            switch action {
            case "screenshot":
                let screenshot = try captureScreenshotForLLM(source: .actionScreenshot)
                return ToolExecutionResult(
                    toolUseId: toolUseId,
                    contentBlocks: [.image(screenshot)],
                    isError: false,
                    stepDescription: "Capture screenshot",
                    generatedQuestions: []
                )
            case "cursor_position", "get_cursor_position", "mouse_position":
                guard let cursor = cursorPositionProvider() else {
                    return ToolExecutionResult(
                        toolUseId: toolUseId,
                        contentBlocks: [.text("Failed to read current cursor position.")],
                        isError: true,
                        stepDescription: nil,
                        generatedQuestions: ["Action '\(action)' failed because cursor position could not be read. What should I do instead?"]
                    )
                }

                let mapped = mapToToolCoordinates(x: cursor.x, y: cursor.y)
                let payload = CursorPositionToolResultPayload(x: mapped.x, y: mapped.y)
                let payloadText = (try? String(data: jsonEncoder.encode(payload), encoding: .utf8)) ?? "{\"x\":\(mapped.x),\"y\":\(mapped.y)}"
                return ToolExecutionResult(
                    toolUseId: toolUseId,
                    contentBlocks: [.text(payloadText)],
                    isError: false,
                    stepDescription: "Read cursor position (\(mapped.x), \(mapped.y))",
                    generatedQuestions: []
                )
            case "mouse_move", "move_mouse", "move":
                guard let (x, y) = extractPoint(from: object) else {
                    return invalidInputResult(toolUseId: toolUseId, action: action)
                }
                let mapped = mapToScreenCoordinates(x: x, y: y)
                try executor.moveMouse(x: mapped.x, y: mapped.y)
                return successWithOptionalScreenshot(toolUseId: toolUseId, stepDescription: "Move mouse to (\(mapped.x), \(mapped.y))")
            case "left_click":
                guard let (x, y) = extractPoint(from: object) else {
                    return invalidInputResult(toolUseId: toolUseId, action: action)
                }
                let mapped = mapToScreenCoordinates(x: x, y: y)
                try executor.click(x: mapped.x, y: mapped.y)
                return successWithOptionalScreenshot(toolUseId: toolUseId, stepDescription: "Click at (\(mapped.x), \(mapped.y))")
            case "right_click":
                guard let (x, y) = extractPoint(from: object) else {
                    return invalidInputResult(toolUseId: toolUseId, action: action)
                }
                let mapped = mapToScreenCoordinates(x: x, y: y)
                try executor.rightClick(x: mapped.x, y: mapped.y)
                return successWithOptionalScreenshot(toolUseId: toolUseId, stepDescription: "Right click at (\(mapped.x), \(mapped.y))")
            case "double_click":
                guard let (x, y) = extractPoint(from: object) else {
                    return invalidInputResult(toolUseId: toolUseId, action: action)
                }
                let mapped = mapToScreenCoordinates(x: x, y: y)
                try executor.click(x: mapped.x, y: mapped.y)
                try executor.click(x: mapped.x, y: mapped.y)
                return successWithOptionalScreenshot(toolUseId: toolUseId, stepDescription: "Double click at (\(mapped.x), \(mapped.y))")
            case "type":
                guard let text = object["text"]?.stringValue,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return invalidInputResult(toolUseId: toolUseId, action: action)
                }
                recordTrace(kind: .info, "Typing uses clipboard paste (cmd+v) with clipboard restore for reliability.")
                try executor.typeText(text)
                return successWithOptionalScreenshot(toolUseId: toolUseId, stepDescription: "Type text '\(text)'")
            case "key":
                guard let raw = firstStringValue(from: object, keys: ["key", "text", "keys"]),
                      let shortcut = parseShortcut(raw) else {
                    return invalidInputResult(toolUseId: toolUseId, action: action)
                }
                try executor.sendShortcut(
                    key: shortcut.key,
                    command: shortcut.command,
                    option: shortcut.option,
                    control: shortcut.control,
                    shift: shortcut.shift
                )
                return successWithOptionalScreenshot(toolUseId: toolUseId, stepDescription: "Press shortcut '\(raw)'")
            case "open_app":
                guard let appName = firstStringValue(from: object, keys: ["app", "name"]) else {
                    return invalidInputResult(toolUseId: toolUseId, action: action)
                }
                try executor.openApp(named: appName)
                return successWithOptionalScreenshot(toolUseId: toolUseId, stepDescription: "Open app '\(appName)'")
            case "open_url":
                guard let urlRaw = firstStringValue(from: object, keys: ["url"]),
                      let url = URL(string: urlRaw) else {
                    return invalidInputResult(toolUseId: toolUseId, action: action)
                }
                try executor.openURL(url)
                return successWithOptionalScreenshot(toolUseId: toolUseId, stepDescription: "Open URL '\(url.absoluteString)'")
            case "scroll":
                // Accept multiple schema variants:
                // - { action:"scroll", delta_x/delta_y }
                // - { action:"scroll", scroll_x/scroll_y }
                // - { action:"scroll", direction:"down", amount: 600 }
                // - (optional) { x/y or coordinate:[x,y] } to scroll at a specific point (we move the mouse first).
                if let (x, y) = extractPoint(from: object) {
                    let mapped = mapToScreenCoordinates(x: x, y: y)
                    try executor.moveMouse(x: mapped.x, y: mapped.y)
                }

                guard let (dx, dy) = extractScrollDelta(from: object) else {
                    return invalidInputResult(toolUseId: toolUseId, action: action)
                }

                try executor.scroll(deltaX: dx, deltaY: dy)
                return successWithOptionalScreenshot(toolUseId: toolUseId, stepDescription: "Scroll (\(dx), \(dy))")
            case "wait":
                let seconds = max(0.1, object["seconds"]?.doubleValue ?? object["duration"]?.doubleValue ?? 1.0)
                let nanos = UInt64(seconds * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanos)
                return successWithOptionalScreenshot(toolUseId: toolUseId, stepDescription: "Wait \(String(format: "%.1f", seconds))s")
            default:
                return ToolExecutionResult(
                    toolUseId: toolUseId,
                    contentBlocks: [.text("Unsupported computer action '\(action)'.")],
                    isError: true,
                    stepDescription: nil,
                    generatedQuestions: ["Action '\(action)' is unsupported. What should I do instead?"]
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return ToolExecutionResult(
                toolUseId: toolUseId,
                contentBlocks: [.text("Action '\(action)' failed: \(error.localizedDescription)")],
                isError: true,
                stepDescription: nil,
                generatedQuestions: ["Execution failed for action '\(action)'. What should I do instead?"]
            )
        }
    }

    private struct CursorPositionToolResultPayload: Encodable {
        var x: Int
        var y: Int
    }

    private struct TerminalExecToolResultPayload: Encodable {
        var ok: Bool
        var exitCode: Int
        var timedOut: Bool
        var stdout: String
        var stderr: String
        var truncated: Bool

        enum CodingKeys: String, CodingKey {
            case ok
            case exitCode = "exit_code"
            case timedOut = "timed_out"
            case stdout
            case stderr
            case truncated
        }
    }

    private struct TerminalCommandExecutionResult {
        var exitCode: Int32
        var timedOut: Bool
        var stdout: Data
        var stderr: Data
        var truncated: Bool
    }

    private final class PipeCollector {
        private let lock = NSLock()
        private let maxBytes: Int
        private(set) var truncated: Bool = false
        private var buffer = Data()

        init(maxBytes: Int) {
            self.maxBytes = max(0, maxBytes)
        }

        func append(_ chunk: Data) {
            lock.lock()
            defer { lock.unlock() }

            guard maxBytes > 0 else {
                truncated = true
                return
            }

            if buffer.count >= maxBytes {
                truncated = true
                return
            }

            let remaining = maxBytes - buffer.count
            if chunk.count <= remaining {
                buffer.append(chunk)
            } else {
                buffer.append(chunk.prefix(remaining))
                truncated = true
            }
        }

        func snapshot() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return buffer
        }
    }

    private static let terminalExecMaxCapturedOutputBytes = 64 * 1024
    private static let terminalExecDefaultTimeoutSeconds = 30.0
    private static let terminalExecMaxTimeoutSeconds = 120.0
    private static let terminalExecAlwaysVisualExecutables: Set<String> = [
        "osascript",
        "cliclick"
    ]
    private static let terminalExecVisualCommandKeywords: [String] = [
        "system events",
        "ui element",
        "click",
        "keystroke",
        "key code",
        "dock",
        "window",
        "menu bar",
        "mouse",
        "cursor",
        "screenshot",
        "screen shot",
        "screencapture"
    ]

    private func executeTerminalExecToolUse(toolUseId: String, input: JSONValue?) async -> ToolExecutionResult {
        guard let object = input?.objectValue else {
            return ToolExecutionResult(
                toolUseId: toolUseId,
                contentBlocks: [.text("Terminal tool input was invalid.")],
                isError: true,
                stepDescription: nil,
                generatedQuestions: ["Terminal tool input from model was invalid. What should I do?"]
            )
        }

        guard let executableRaw = object["executable"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !executableRaw.isEmpty else {
            return ToolExecutionResult(
                toolUseId: toolUseId,
                contentBlocks: [.text("Terminal tool input missing 'executable'.")],
                isError: true,
                stepDescription: nil,
                generatedQuestions: ["Model omitted the terminal executable to run. What should I do?"]
            )
        }

        var args: [String] = []
        if let argsValue = object["args"] {
            guard let array = argsValue.arrayValue else {
                return ToolExecutionResult(
                    toolUseId: toolUseId,
                    contentBlocks: [.text("Terminal tool input field 'args' must be an array of strings.")],
                    isError: true,
                    stepDescription: nil,
                    generatedQuestions: ["Terminal tool input field 'args' was invalid. What should I do?"]
                )
            }
            for value in array {
                guard let s = value.stringValue else {
                    return ToolExecutionResult(
                        toolUseId: toolUseId,
                        contentBlocks: [.text("Terminal tool input field 'args' must contain only strings.")],
                        isError: true,
                        stepDescription: nil,
                        generatedQuestions: ["Terminal tool input field 'args' was invalid. What should I do?"]
                    )
                }
                args.append(s)
            }
        }

        let timeoutRaw = object["timeout_seconds"]?.doubleValue ?? Self.terminalExecDefaultTimeoutSeconds
        let timeoutSeconds = min(Self.terminalExecMaxTimeoutSeconds, max(0.1, timeoutRaw))

        if let policyViolationMessage = validateTerminalExecPolicy(executable: executableRaw, args: args) {
            return ToolExecutionResult(
                toolUseId: toolUseId,
                contentBlocks: [.text(policyViolationMessage)],
                isError: true,
                stepDescription: nil,
                generatedQuestions: []
            )
        }

        guard let resolvedExecutable = resolveTerminalExecutable(executableRaw) else {
            return ToolExecutionResult(
                toolUseId: toolUseId,
                contentBlocks: [.text("Executable '\(executableRaw)' was not found or is not executable.")],
                isError: true,
                stepDescription: nil,
                generatedQuestions: ["Terminal command executable was not found ('\(executableRaw)'). What should I do instead?"]
            )
        }

        let commandSummary = summarizeTerminalCommand(executablePath: resolvedExecutable, args: args)
        recordTrace(kind: .info, "Terminal exec requested: \(commandSummary)")

        do {
            let exec = try await runTerminalCommand(executablePath: resolvedExecutable, args: args, timeoutSeconds: timeoutSeconds)
            let stdout = String(decoding: exec.stdout, as: UTF8.self)
            let stderr = String(decoding: exec.stderr, as: UTF8.self)

            let payload = TerminalExecToolResultPayload(
                ok: (exec.exitCode == 0) && !exec.timedOut,
                exitCode: Int(exec.exitCode),
                timedOut: exec.timedOut,
                stdout: stdout,
                stderr: stderr,
                truncated: exec.truncated
            )

            let payloadText: String
            if let json = try? String(data: jsonEncoder.encode(payload), encoding: .utf8) {
                payloadText = json
            } else {
                payloadText = "{\"ok\":false,\"exit_code\":-1,\"timed_out\":false,\"stdout\":\"\",\"stderr\":\"Failed to encode terminal tool result.\",\"truncated\":false}"
            }

            return ToolExecutionResult(
                toolUseId: toolUseId,
                contentBlocks: [.text(payloadText)],
                isError: !payload.ok,
                stepDescription: "Terminal exec: \(commandSummary)",
                generatedQuestions: payload.ok ? [] : ["Terminal command failed (\(commandSummary)). What should I do instead?"]
            )
        } catch {
            return ToolExecutionResult(
                toolUseId: toolUseId,
                contentBlocks: [.text("Terminal exec failed: \(error.localizedDescription)")],
                isError: true,
                stepDescription: nil,
                generatedQuestions: ["Terminal exec failed for (\(commandSummary)). What should I do instead?"]
            )
        }
    }

    private func resolveTerminalExecutable(_ raw: String) -> String? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        if cleaned.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: cleaned) ? cleaned : nil
        }

        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for directory in pathEnv.split(separator: ":").map(String.init) {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(cleaned, isDirectory: false)
                .path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private func validateTerminalExecPolicy(executable: String, args: [String]) -> String? {
        let executableName = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
        let commandLineLower = ([executableName] + args).joined(separator: " ").lowercased()

        if Self.terminalExecAlwaysVisualExecutables.contains(executableName) {
            return "Terminal command '\(executableName)' is blocked for UI/visual automation. Use tool 'computer' for on-screen actions (find/hover/click/scroll/type based on screenshots)."
        }

        if Self.terminalExecVisualCommandKeywords.contains(where: { commandLineLower.contains($0) }) {
            return "Terminal command appears to target visual UI state. Use tool 'computer' for on-screen actions and coordinates."
        }

        return nil
    }

    private func summarizeTerminalCommand(executablePath: String, args: [String]) -> String {
        let cmd = ([URL(fileURLWithPath: executablePath).lastPathComponent] + args).joined(separator: " ")
        return truncate(cmd, limit: 220)
    }

    private func runTerminalCommand(executablePath: String, args: [String], timeoutSeconds: Double) async throws -> TerminalCommandExecutionResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let result = try self.runTerminalCommandSync(executablePath: executablePath, args: args, timeoutSeconds: timeoutSeconds)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runTerminalCommandSync(executablePath: String, args: [String], timeoutSeconds: Double) throws -> TerminalCommandExecutionResult {
        let exeURL = URL(fileURLWithPath: executablePath)

        let process = Process()
        process.executableURL = exeURL
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutCollector = PipeCollector(maxBytes: Self.terminalExecMaxCapturedOutputBytes)
        let stderrCollector = PipeCollector(maxBytes: Self.terminalExecMaxCapturedOutputBytes)

        let terminationSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            terminationSemaphore.signal()
        }

        try process.run()

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let handle = stdoutPipe.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                stdoutCollector.append(chunk)
            }
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let handle = stderrPipe.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                stderrCollector.append(chunk)
            }
            group.leave()
        }

        var timedOut = false
        if terminationSemaphore.wait(timeout: .now() + max(0.1, timeoutSeconds)) != .success {
            timedOut = true
            if process.isRunning {
                process.terminate()
            }
            _ = terminationSemaphore.wait(timeout: .now() + 2.0)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = terminationSemaphore.wait(timeout: .now() + 1.0)
            }
        }

        group.wait()

        let truncated = stdoutCollector.truncated || stderrCollector.truncated
        return TerminalCommandExecutionResult(
            exitCode: process.terminationStatus,
            timedOut: timedOut,
            stdout: stdoutCollector.snapshot(),
            stderr: stderrCollector.snapshot(),
            truncated: truncated
        )
    }

    private func mapToToolCoordinates(x: Int, y: Int) -> (x: Int, y: Int) {
        let invScaleX = coordinateScaleX == 0 ? 1.0 : coordinateScaleX
        let invScaleY = coordinateScaleY == 0 ? 1.0 : coordinateScaleY
        let scaledX = Int((Double(x) / invScaleX).rounded())
        let scaledY = Int((Double(y) / invScaleY).rounded())

        if toolDisplayWidthPx > 0, toolDisplayHeightPx > 0 {
            return (
                max(0, min(toolDisplayWidthPx - 1, scaledX)),
                max(0, min(toolDisplayHeightPx - 1, scaledY))
            )
        }

        return (scaledX, scaledY)
    }

    private func mapToScreenCoordinates(x: Int, y: Int) -> (x: Int, y: Int) {
        // Anthropic computer-use coordinates are expressed in the tool display size we send. If we downscale screenshots
        // to fit payload limits, scale coordinates back up to the system's CGEvent injection coordinate space.
        let scaledX = Int((Double(x) * coordinateScaleX).rounded())
        let scaledY = Int((Double(y) * coordinateScaleY).rounded())

        if coordinateSpaceWidthPx > 0, coordinateSpaceHeightPx > 0 {
            let clampedX = max(0, min(coordinateSpaceWidthPx - 1, scaledX))
            let clampedY = max(0, min(coordinateSpaceHeightPx - 1, scaledY))
            if clampedX != scaledX || clampedY != scaledY {
                recordTrace(
                    kind: .info,
                    "Clamped tool coordinates from (\(scaledX), \(scaledY)) to (\(clampedX), \(clampedY)) for coordSpace=\(coordinateSpaceWidthPx)x\(coordinateSpaceHeightPx)."
                )
            }
            return (clampedX, clampedY)
        }

        return (scaledX, scaledY)
    }

    private func invalidInputResult(toolUseId: String, action: String) -> ToolExecutionResult {
        ToolExecutionResult(
            toolUseId: toolUseId,
            contentBlocks: [.text("Action '\(action)' had invalid input.")],
            isError: true,
            stepDescription: nil,
            generatedQuestions: ["Action '\(action)' had invalid input from the model. How should I proceed?"]
        )
    }

    private func successWithOptionalScreenshot(toolUseId: String, stepDescription: String) -> ToolExecutionResult {
        var content: [AnthropicToolResultContent] = [.text("Done")]
        if let screenshot = try? captureScreenshotForLLM(source: .postActionSnapshot) {
            content.append(.image(screenshot))
        }
        return ToolExecutionResult(
            toolUseId: toolUseId,
            contentBlocks: content,
            isError: false,
            stepDescription: stepDescription,
            generatedQuestions: []
        )
    }

    private func captureScreenshotForLLM(source: LLMScreenshotSource) throws -> AnthropicCapturedScreenshot {
        let screenshot = try screenshotProvider()
        if let encodedData = Data(base64Encoded: screenshot.base64Data) {
            screenshotLogSink?(
                LLMScreenshotLogEntry(
                    source: source,
                    mediaType: screenshot.mediaType,
                    width: screenshot.width,
                    height: screenshot.height,
                    captureWidthPx: screenshot.captureWidthPx,
                    captureHeightPx: screenshot.captureHeightPx,
                    coordinateSpaceWidthPx: screenshot.coordinateSpaceWidthPx,
                    coordinateSpaceHeightPx: screenshot.coordinateSpaceHeightPx,
                    rawByteCount: screenshot.byteCount,
                    base64ByteCount: screenshot.base64Data.utf8.count,
                    imageData: encodedData
                )
            )
        }
        return screenshot
    }

    private struct CompactedConversationMessages {
        var messages: [AnthropicConversationMessage]
        var removedImageCount: Int
    }

    private func compactMessagesKeepingLatestImage(_ messages: [AnthropicConversationMessage]) -> CompactedConversationMessages {
        var compacted = messages
        var shouldKeepLatestImage = true
        var removedImageCount = 0

        for messageIndex in compacted.indices.reversed() {
            var message = compacted[messageIndex]
            var content = message.content

            for contentIndex in content.indices.reversed() {
                var block = content[contentIndex]

                if block.type == "image" {
                    if shouldKeepLatestImage {
                        shouldKeepLatestImage = false
                    } else {
                        content.remove(at: contentIndex)
                        removedImageCount += 1
                    }
                    continue
                }

                guard block.type == "tool_result", var toolContent = block.content else {
                    continue
                }

                var removedInBlock = 0
                for toolContentIndex in toolContent.indices.reversed() {
                    if toolContent[toolContentIndex].type == "image" {
                        if shouldKeepLatestImage {
                            shouldKeepLatestImage = false
                        } else {
                            toolContent.remove(at: toolContentIndex)
                            removedInBlock += 1
                        }
                    }
                }

                guard removedInBlock > 0 else { continue }

                removedImageCount += removedInBlock
                if toolContent.isEmpty {
                    toolContent = [.text("Previous screenshot omitted to reduce payload; latest screenshot retained.")]
                }
                block.content = toolContent
                content[contentIndex] = block
            }

            message.content = content
            compacted[messageIndex] = message
        }

        return CompactedConversationMessages(messages: compacted, removedImageCount: removedImageCount)
    }

    private func parseCompletion(from text: String) -> CompletionResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return CompletionResult(
                outcome: .needsClarification,
                summary: nil,
                questions: ["Execution ended without a final status. What should I do next?"],
                errorMessage: "Execution ended without a final status."
            )
        }

        if let payloadData = extractJSONPayloadData(from: trimmed),
           let payload = try? jsonDecoder.decode(ToolLoopCompletionPayload.self, from: payloadData) {
            let questions = payload.questions?.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
            return CompletionResult(
                outcome: mapStatus(payload.status),
                summary: payload.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
                questions: questions,
                errorMessage: payload.error?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return CompletionResult(
            outcome: .needsClarification,
            summary: trimmed,
            questions: ["Execution result was not machine-readable. Please clarify what should happen next."],
            errorMessage: "Final model response was not valid completion JSON."
        )
    }

    private func resolveAPIKey() throws -> String {
        do {
            guard let raw = try apiKeyStore.readKey(for: .anthropic) else {
                throw AnthropicExecutionPlannerError.missingAPIKey
            }
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                throw AnthropicExecutionPlannerError.missingAPIKey
            }
            return key
        } catch let error as AnthropicExecutionPlannerError {
            throw error
        } catch {
            throw AnthropicExecutionPlannerError.failedToReadAPIKey
        }
    }

    private func loadPromptTemplate() throws -> PromptTemplate {
        do {
            return try promptCatalog.loadPrompt(named: promptName)
        } catch {
            throw AnthropicExecutionPlannerError.failedToLoadPrompt(promptName)
        }
    }

    private func renderPrompt(_ template: String, taskMarkdown: String) -> String {
        template
            .replacingOccurrences(of: "{{OS_VERSION}}", with: ProcessInfo.processInfo.operatingSystemVersionString)
            .replacingOccurrences(of: "{{TASK_MARKDOWN}}", with: taskMarkdown)
    }

    private func mapStatus(_ raw: String) -> AutomationRunOutcome {
        switch raw.uppercased() {
        case "SUCCESS":
            return .success
        case "FAILED":
            return .failed
        default:
            return .needsClarification
        }
    }

    private func extractJSONPayloadData(from content: String) -> Data? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            return trimmed.data(using: .utf8)
        }

        if let fencedRange = trimmed.range(of: "```json"),
           let closingRange = trimmed.range(of: "```", range: fencedRange.upperBound..<trimmed.endIndex) {
            let payload = String(trimmed[fencedRange.upperBound..<closingRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if payload.hasPrefix("{"), payload.hasSuffix("}") {
                return payload.data(using: .utf8)
            }
        }

        guard let firstBrace = trimmed.firstIndex(of: "{"),
              let lastBrace = trimmed.lastIndex(of: "}") else {
            return nil
        }
        let payload = String(trimmed[firstBrace...lastBrace])
        return payload.data(using: .utf8)
    }

    private func serverMessage(from data: Data, statusCode: Int) -> String {
        if let payload = try? jsonDecoder.decode(AnthropicErrorEnvelope.self, from: data),
           let message = payload.error?.message,
           !message.isEmpty {
            return message
        }
        return "HTTP \(statusCode)"
    }

    nonisolated private static func currentCursorPosition() -> (x: Int, y: Int)? {
        if let event = CGEvent(source: nil) {
            let point = event.location
            return (Int(point.x.rounded()), Int(point.y.rounded()))
        }
        let point = NSEvent.mouseLocation
        return (Int(point.x.rounded()), Int(point.y.rounded()))
    }

    nonisolated private static func captureMainDisplayScreenshot() throws -> AnthropicCapturedScreenshot {
        try captureMainDisplayScreenshot(excludingWindowNumber: nil)
    }

    nonisolated static func captureMainDisplayScreenshot(excludingWindowNumber: Int?) throws -> AnthropicCapturedScreenshot {
        let mainDisplayBounds = CGDisplayBounds(CGMainDisplayID())
        let coordSpaceW = max(1, Int(mainDisplayBounds.width.rounded()))
        let coordSpaceH = max(1, Int(mainDisplayBounds.height.rounded()))

        let capture: DesktopScreenshotCapture
        do {
            capture = try DesktopScreenshotService.captureMainDisplayPNG(excludingWindowNumber: excludingWindowNumber)
        } catch {
            throw AnthropicExecutionPlannerError.screenshotCaptureFailed
        }

        // Anthropic computer-use images are capped at 5 MB for the base64 payload, not raw bytes.
        // Prefer a deterministic downscale (if needed) + JPEG encode so the tool coordinate system is stable.
        let maxEncodedBytes = 5 * 1024 * 1024
        let (data, mediaType, width, height) = try encodeScreenshotForAnthropic(
            pngData: capture.pngData,
            captureWidthPx: capture.width,
            captureHeightPx: capture.height,
            preferredMaxWidthPx: coordSpaceW,
            preferredMaxHeightPx: coordSpaceH,
            maxEncodedBytes: maxEncodedBytes
        )

        return AnthropicCapturedScreenshot(
            width: width,
            height: height,
            captureWidthPx: capture.width,
            captureHeightPx: capture.height,
            coordinateSpaceWidthPx: coordSpaceW,
            coordinateSpaceHeightPx: coordSpaceH,
            mediaType: mediaType,
            base64Data: data.base64EncodedString(),
            byteCount: data.count
        )
    }

    nonisolated private static func encodeScreenshotForAnthropic(
        pngData: Data,
        captureWidthPx: Int,
        captureHeightPx: Int,
        preferredMaxWidthPx: Int,
        preferredMaxHeightPx: Int,
        maxEncodedBytes: Int
    ) throws -> (Data, String, Int, Int) {
        guard
            let source = CGImageSourceCreateWithData(pngData as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw AnthropicExecutionPlannerError.screenshotCaptureFailed
        }

        let maxRawBytes = maxRawByteCountForBase64Limit(maxEncodedBytes)
        guard maxRawBytes > 0 else {
            throw AnthropicExecutionPlannerError.screenshotTooLarge(maxEncodedBytes)
        }

        // Deterministic downscale: constrain to (a) the CGEvent injection coordinate space
        // and (b) a max long side to keep payloads predictable.
        let maxSide = 2560.0
        let rawW = Double(max(1, captureWidthPx))
        let rawH = Double(max(1, captureHeightPx))

        let maxW = Double(max(1, min(preferredMaxWidthPx, Int(maxSide))))
        let maxH = Double(max(1, min(preferredMaxHeightPx, Int(maxSide))))
        let scale = min(1.0, min(maxW / rawW, maxH / rawH))
        let targetW = max(1, Int((rawW * scale).rounded()))
        let targetH = max(1, Int((rawH * scale).rounded()))

        let toEncode: CGImage
        if targetW == captureWidthPx, targetH == captureHeightPx {
            // If the raw PNG already fits and we don't need resizing, keep PNG.
            if pngData.count <= maxRawBytes,
               base64EncodedByteCount(forRawByteCount: pngData.count) <= maxEncodedBytes {
                return (pngData, "image/png", captureWidthPx, captureHeightPx)
            }
            toEncode = cgImage
        } else if let scaled = scaleCGImage(cgImage, width: targetW, height: targetH) {
            toEncode = scaled
        } else {
            throw AnthropicExecutionPlannerError.screenshotCaptureFailed
        }

        // Encode as JPEG; vary quality to fit <= 5 MB.
        for quality in [0.80, 0.72, 0.65, 0.58, 0.50, 0.42, 0.35, 0.28, 0.22] as [CGFloat] {
            if let data = encodeJPEG(cgImage: toEncode, quality: quality),
               data.count <= maxRawBytes,
               base64EncodedByteCount(forRawByteCount: data.count) <= maxEncodedBytes {
                return (data, "image/jpeg", toEncode.width, toEncode.height)
            }
        }

        throw AnthropicExecutionPlannerError.screenshotTooLarge(maxEncodedBytes)
    }

    nonisolated static func base64EncodedByteCount(forRawByteCount rawByteCount: Int) -> Int {
        guard rawByteCount > 0 else { return 0 }
        let base64Blocks = (rawByteCount + 2) / 3
        return base64Blocks * 4
    }

    nonisolated static func maxRawByteCountForBase64Limit(_ base64ByteLimit: Int) -> Int {
        guard base64ByteLimit > 0 else { return 0 }
        return (base64ByteLimit / 4) * 3
    }

    nonisolated private static func encodeJPEG(cgImage: CGImage, quality: CGFloat) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            return nil
        }
        return out as Data
    }

    nonisolated private static func scaleCGImage(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    private func firstStringValue(from object: [String: JSONValue], keys: [String]) -> String? {
        for key in keys {
            guard let value = object[key]?.stringValue else {
                continue
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private func parseShortcut(_ raw: String) -> (key: String, command: Bool, option: Bool, control: Bool, shift: Bool)? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        let pieces = normalized
            .split(separator: "+")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        var command = false
        var option = false
        var control = false
        var shift = false
        var key: String?

        for piece in pieces {
            switch piece {
            case "cmd", "command", "super", "win", "windows", "meta", "⌘":
                command = true
            case "opt", "option", "alt", "⌥":
                option = true
            case "ctrl", "control", "⌃":
                control = true
            case "shift", "⇧":
                shift = true
            case "enter":
                key = "return"
            case "space", "spacebar":
                key = " "
            case "esc":
                key = "escape"
            default:
                key = piece
            }
        }

        if key == nil, !pieces.isEmpty {
            key = pieces.last
        }

        guard let resolvedKey = key else { return nil }
        return (resolvedKey, command, option, control, shift)
    }

    private func dedupe(_ questions: [String]) -> [String] {
        var seen: Set<String> = []
        var output: [String] = []
        for question in questions {
            let normalized = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else {
                continue
            }
            output.append(question.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    private func recordTrace(kind: ExecutionTraceKind, _ message: String) {
        traceSink?(ExecutionTraceEntry(kind: kind, message: truncate(message, limit: 900)))
    }

    private func truncate(_ message: String, limit: Int) -> String {
        let cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > limit else {
            return cleaned
        }
        let prefix = cleaned.prefix(limit)
        return "\(prefix)…"
    }

    private func summarizeAssistantResponse(turn: Int, content: [AnthropicMessageContent]) -> String {
        let toolUses = content.filter { $0.type == "tool_use" }
        let text = content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !toolUses.isEmpty {
            let toolSummary = toolUses.map { summarizeToolUse($0) }.joined(separator: " | ")
            return "Turn \(turn): tool_use x\(toolUses.count): \(toolSummary)"
        }

        if !text.isEmpty {
            return "Turn \(turn): text: \(truncate(text, limit: 400))"
        }

        let types = content.map(\.type).joined(separator: ",")
        return "Turn \(turn): no tool_use; content types: \(types)"
    }

    private func summarizeToolUse(_ block: AnthropicMessageContent) -> String {
        let toolName = (block.name ?? "unknown").trimmingCharacters(in: .whitespacesAndNewlines)
        let object = block.input?.objectValue ?? [:]

        if toolName.lowercased() == "terminal_exec" {
            let executable = (object["executable"]?.stringValue ?? "?").trimmingCharacters(in: .whitespacesAndNewlines)
            let args = object["args"]?.arrayValue?.compactMap(\.stringValue) ?? []
            let argsPreview = args.prefix(6).joined(separator: " ")
            let suffix = args.count > 6 ? " …" : ""
            return "terminal_exec(executable=\"\(truncate(executable, limit: 80))\", args=\"\(truncate(argsPreview + suffix, limit: 160))\")"
        }

        let action = (object["action"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if action.isEmpty {
            return "\(toolName): (missing action)"
        }

        switch action.lowercased() {
        case "mouse_move", "move_mouse", "move", "left_click", "double_click", "right_click":
            let point = extractPoint(from: object)
            let x = point?.0
            let y = point?.1
            return "\(toolName).\(action)(x=\(x.map(String.init) ?? "?"),y=\(y.map(String.init) ?? "?"))"
        case "scroll":
            if let (dx, dy) = extractScrollDelta(from: object) {
                return "\(toolName).scroll(dx=\(dx),dy=\(dy))"
            }
            let direction = object["direction"]?.stringValue ?? "?"
            let amount = object["amount"]?.doubleValue ?? object["scroll_amount"]?.doubleValue ?? object["pixels"]?.doubleValue
            if let amount {
                return "\(toolName).scroll(direction=\(direction),amount=\(String(format: "%.0f", amount)))"
            }
            return "\(toolName).scroll"
        case "type":
            let text = object["text"]?.stringValue ?? ""
            return "\(toolName).type(text=\"\(truncate(text, limit: 80))\")"
        case "key":
            let raw = firstStringValue(from: object, keys: ["key", "text", "keys"]) ?? ""
            return "\(toolName).key(\"\(truncate(raw, limit: 80))\")"
        case "open_app":
            let app = firstStringValue(from: object, keys: ["app", "name"]) ?? ""
            return "\(toolName).open_app(\"\(truncate(app, limit: 80))\")"
        case "open_url":
            let url = firstStringValue(from: object, keys: ["url"]) ?? ""
            return "\(toolName).open_url(\"\(truncate(url, limit: 140))\")"
        case "wait":
            let seconds = object["seconds"]?.doubleValue ?? object["duration"]?.doubleValue
            if let seconds {
                return "\(toolName).wait(\(String(format: "%.1f", seconds))s)"
            }
            return "\(toolName).wait"
        case "cursor_position", "get_cursor_position", "mouse_position":
            return "\(toolName).cursor_position"
        case "screenshot":
            return "\(toolName).screenshot"
        default:
            return "\(toolName).\(action)"
        }
    }

    private func extractScrollDelta(from object: [String: JSONValue]) -> (Int, Int)? {
        let dx = object["delta_x"]?.intValue ?? object["scroll_x"]?.intValue ?? object["dx"]?.intValue
        let dy = object["delta_y"]?.intValue ?? object["scroll_y"]?.intValue ?? object["dy"]?.intValue

        if let dx, let dy {
            return (dx, dy)
        }
        if let dy {
            return (0, dy)
        }
        if let dx {
            return (dx, 0)
        }

        // Direction + amount variant.
        if let direction = object["direction"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           let amountRaw = object["amount"]?.doubleValue ?? object["scroll_amount"]?.doubleValue ?? object["pixels"]?.doubleValue {
            let amount = Int(amountRaw.rounded())
            switch direction {
            case "down":
                return (0, -abs(amount))
            case "up":
                return (0, abs(amount))
            case "left":
                return (-abs(amount), 0)
            case "right":
                return (abs(amount), 0)
            default:
                break
            }
        }

        return nil
    }

    private func extractPoint(from object: [String: JSONValue]) -> (Int, Int)? {
        if let x = object["x"]?.intValue, let y = object["y"]?.intValue {
            return (x, y)
        }

        // Common Anthropic computer-use variants observed in the wild:
        // - coordinate: [x, y]
        // - coordinate: {x:..., y:...}
        // - position/point/location: ...
        for key in ["coordinate", "coordinates", "position", "point", "location", "pos"] {
            guard let value = object[key] else { continue }
            if let point = extractPoint(from: value) {
                return point
            }
        }

        return nil
    }

    private func extractPoint(from value: JSONValue) -> (Int, Int)? {
        if let array = value.arrayValue, array.count >= 2, let x = array[0].intValue, let y = array[1].intValue {
            return (x, y)
        }

        if let obj = value.objectValue {
            let x = obj["x"]?.intValue ?? obj["left"]?.intValue
            let y = obj["y"]?.intValue ?? obj["top"]?.intValue
            if let x, let y {
                return (x, y)
            }
        }

        return nil
    }
}

struct AnthropicAutomationEngine: AutomationEngine {
    private let runner: any LLMExecutionToolLoopRunner
    private let executor: any DesktopActionExecutor

    init(
        runner: any LLMExecutionToolLoopRunner,
        executor: any DesktopActionExecutor = SystemDesktopActionExecutor()
    ) {
        self.runner = runner
        self.executor = executor
    }

    func run(taskMarkdown: String) async -> AutomationRunResult {
        do {
            return try await runner.runToolLoop(taskMarkdown: taskMarkdown, executor: executor)
        } catch let error as AnthropicExecutionPlannerError {
            return AutomationRunResult(
                outcome: .failed,
                executedSteps: [],
                generatedQuestions: [],
                errorMessage: error.errorDescription,
                llmSummary: nil
            )
        } catch is CancellationError {
            return AutomationRunResult(
                outcome: .cancelled,
                executedSteps: [],
                generatedQuestions: [],
                errorMessage: nil,
                llmSummary: "Cancelled by user."
            )
        } catch {
            return AutomationRunResult(
                outcome: .failed,
                executedSteps: [],
                generatedQuestions: [],
                errorMessage: "Failed during execution tool loop.",
                llmSummary: nil
            )
        }
    }
}

private struct AnthropicMessagesRequest: Encodable {
    var model: String
    var maxTokens: Int
    var system: String
    var messages: [AnthropicConversationMessage]
    var tools: [AnthropicToolSpec]?

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case tools
    }
}

private struct AnthropicConversationMessage: Codable {
    var role: String
    var content: [AnthropicMessageContent]
}

private enum AnthropicToolSpec: Encodable {
    case computer(AnthropicComputerToolDefinition)
    case function(AnthropicFunctionToolDefinition)

    func encode(to encoder: Encoder) throws {
        switch self {
        case .computer(let tool):
            try tool.encode(to: encoder)
        case .function(let tool):
            try tool.encode(to: encoder)
        }
    }
}

private struct AnthropicComputerToolDefinition: Encodable {
    var type: String
    var name: String
    var displayWidthPx: Int
    var displayHeightPx: Int
    var displayNumber: Int

    enum CodingKeys: String, CodingKey {
        case type
        case name
        case displayWidthPx = "display_width_px"
        case displayHeightPx = "display_height_px"
        case displayNumber = "display_number"
    }
}

private struct AnthropicFunctionToolDefinition: Encodable {
    var name: String
    var description: String
    var inputSchema: AnthropicToolInputSchema

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }
}

private indirect enum AnthropicToolInputSchema: Encodable {
    case object(properties: [String: AnthropicToolInputSchema], required: [String], additionalProperties: Bool)
    case array(items: AnthropicToolInputSchema, description: String?)
    case string(description: String?)
    case number(description: String?)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .object(let properties, let required, let additionalProperties):
            try container.encode("object", forKey: .type)
            try container.encode(properties, forKey: .properties)
            try container.encode(required, forKey: .required)
            try container.encode(additionalProperties, forKey: .additionalProperties)
        case .array(let items, let description):
            try container.encode("array", forKey: .type)
            try container.encode(items, forKey: .items)
            if let description {
                try container.encode(description, forKey: .description)
            }
        case .string(let description):
            try container.encode("string", forKey: .type)
            if let description {
                try container.encode(description, forKey: .description)
            }
        case .number(let description):
            try container.encode("number", forKey: .type)
            if let description {
                try container.encode(description, forKey: .description)
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case description
        case properties
        case required
        case items
        case additionalProperties
    }
}

private struct AnthropicMessagesResponse: Decodable {
    var content: [AnthropicMessageContent]
}

private struct AnthropicMessageContent: Codable {
    var type: String
    var text: String?
    var id: String?
    var name: String?
    var input: JSONValue?
    var source: AnthropicImageSource?
    var toolUseId: String?
    var content: [AnthropicToolResultContent]?
    var isError: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case id
        case name
        case input
        case source
        case toolUseId = "tool_use_id"
        case content
        case isError = "is_error"
    }

    static func text(_ text: String) -> AnthropicMessageContent {
        AnthropicMessageContent(type: "text", text: text, id: nil, name: nil, input: nil, source: nil, toolUseId: nil, content: nil, isError: nil)
    }

    static func image(_ screenshot: AnthropicCapturedScreenshot) -> AnthropicMessageContent {
        AnthropicMessageContent(
            type: "image",
            text: nil,
            id: nil,
            name: nil,
            input: nil,
            source: AnthropicImageSource(type: "base64", mediaType: screenshot.mediaType, data: screenshot.base64Data),
            toolUseId: nil,
            content: nil,
            isError: nil
        )
    }

    static func toolResult(toolUseId: String, content: [AnthropicToolResultContent], isError: Bool) -> AnthropicMessageContent {
        AnthropicMessageContent(
            type: "tool_result",
            text: nil,
            id: nil,
            name: nil,
            input: nil,
            source: nil,
            toolUseId: toolUseId,
            content: content,
            isError: isError
        )
    }
}

private struct AnthropicToolResultContent: Codable {
    var type: String
    var text: String?
    var source: AnthropicImageSource?

    static func text(_ text: String) -> AnthropicToolResultContent {
        AnthropicToolResultContent(type: "text", text: text, source: nil)
    }

    static func image(_ screenshot: AnthropicCapturedScreenshot) -> AnthropicToolResultContent {
        AnthropicToolResultContent(
            type: "image",
            text: nil,
            source: AnthropicImageSource(type: "base64", mediaType: screenshot.mediaType, data: screenshot.base64Data)
        )
    }
}

private struct AnthropicImageSource: Codable {
    var type: String
    var mediaType: String
    var data: String

    enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}

private struct AnthropicErrorEnvelope: Decodable {
    struct ErrorPayload: Decodable {
        var message: String
    }

    var error: ErrorPayload?
}

private struct ToolLoopCompletionPayload: Decodable {
    var status: String
    var summary: String?
    var error: String?
    var questions: [String]?
}

private enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return String(value)
        default:
            return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value):
            return value
        case .string(let value):
            return Double(value)
        default:
            return nil
        }
    }

    var intValue: Int? {
        guard let double = doubleValue else {
            return nil
        }
        return Int(double.rounded())
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }
}
