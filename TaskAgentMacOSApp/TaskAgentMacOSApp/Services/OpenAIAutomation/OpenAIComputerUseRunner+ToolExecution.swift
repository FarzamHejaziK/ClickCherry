import Foundation

extension OpenAIComputerUseRunner {
    func executeFunctionCall(
        _ functionCall: ParsedFunctionCall,
        executor: any DesktopActionExecutor
    ) async throws -> ToolExecutionResult {
        let toolName = functionCall.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard toolName == "desktop_action" || toolName == "terminal_exec" else {
            return ToolExecutionResult(
                callID: functionCall.callID,
                output: makeToolOutput(
                    ok: false,
                    message: "Unsupported tool '\(functionCall.name)'.",
                    error: "unsupported_tool"
                ),
                isError: true,
                stepDescription: nil,
                generatedQuestions: ["Model requested unsupported tool '\(functionCall.name)'. What should I do?"]
            )
        }

        guard
            let argumentsData = functionCall.arguments.data(using: .utf8),
            let object = try? jsonDecoder.decode([String: OpenAIJSONValue].self, from: argumentsData)
        else {
            return ToolExecutionResult(
                callID: functionCall.callID,
                output: makeToolOutput(
                    ok: false,
                    message: "Tool input was invalid JSON.",
                    error: "invalid_input"
                ),
                isError: true,
                stepDescription: nil,
                generatedQuestions: ["Execution input from model was invalid. How should I proceed?"]
            )
        }

        if toolName == "terminal_exec" {
            return await executeTerminalExecFunctionCall(callID: functionCall.callID, input: object, executor: executor)
        }

        let action = (object["action"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !action.isEmpty else {
            return ToolExecutionResult(
                callID: functionCall.callID,
                output: makeToolOutput(
                    ok: false,
                    message: "Tool input missing 'action'.",
                    error: "missing_action"
                ),
                isError: true,
                stepDescription: nil,
                generatedQuestions: ["Model omitted the requested action. What should I do?"]
            )
        }

        do {
            switch action {
            case "screenshot":
                return ToolExecutionResult(
                    callID: functionCall.callID,
                    output: makeToolOutput(ok: true, message: "Captured screenshot."),
                    isError: false,
                    stepDescription: "Capture screenshot",
                    generatedQuestions: []
                )
            case "cursor_position", "get_cursor_position", "mouse_position":
                guard let cursor = cursorPositionProvider() else {
                    return ToolExecutionResult(
                        callID: functionCall.callID,
                        output: makeToolOutput(ok: false, message: "Failed to read current cursor position.", error: "cursor_unavailable"),
                        isError: true,
                        stepDescription: nil,
                        generatedQuestions: ["Action '\(action)' failed because cursor position could not be read. What should I do instead?"]
                    )
                }
                let mapped = mapToToolCoordinates(x: cursor.x, y: cursor.y)
                let payload = makeToolOutput(
                    ok: true,
                    message: "Cursor position",
                    data: ["x": mapped.x, "y": mapped.y]
                )
                return ToolExecutionResult(
                    callID: functionCall.callID,
                    output: payload,
                    isError: false,
                    stepDescription: "Read cursor position (\(mapped.x), \(mapped.y))",
                    generatedQuestions: []
                )
            case "mouse_move", "move_mouse", "move":
                guard let (x, y) = extractPoint(from: object) else {
                    return invalidInputResult(callID: functionCall.callID, action: action)
                }
                let mapped = mapToScreenCoordinates(x: x, y: y)
                try executor.moveMouse(x: mapped.x, y: mapped.y)
                return successResult(callID: functionCall.callID, stepDescription: "Move mouse to (\(mapped.x), \(mapped.y))")
            case "left_click":
                guard let (x, y) = extractPoint(from: object) else {
                    return invalidInputResult(callID: functionCall.callID, action: action)
                }
                let mapped = mapToScreenCoordinates(x: x, y: y)
                try executor.click(x: mapped.x, y: mapped.y)
                return successResult(callID: functionCall.callID, stepDescription: "Click at (\(mapped.x), \(mapped.y))")
            case "right_click":
                guard let (x, y) = extractPoint(from: object) else {
                    return invalidInputResult(callID: functionCall.callID, action: action)
                }
                let mapped = mapToScreenCoordinates(x: x, y: y)
                try executor.rightClick(x: mapped.x, y: mapped.y)
                return successResult(callID: functionCall.callID, stepDescription: "Right click at (\(mapped.x), \(mapped.y))")
            case "double_click":
                guard let (x, y) = extractPoint(from: object) else {
                    return invalidInputResult(callID: functionCall.callID, action: action)
                }
                let mapped = mapToScreenCoordinates(x: x, y: y)
                try executor.click(x: mapped.x, y: mapped.y)
                try executor.click(x: mapped.x, y: mapped.y)
                return successResult(callID: functionCall.callID, stepDescription: "Double click at (\(mapped.x), \(mapped.y))")
            case "type":
                guard let text = object["text"]?.stringValue,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return invalidInputResult(callID: functionCall.callID, action: action)
                }
                recordTrace(kind: .info, "Typing uses clipboard paste (cmd+v) with clipboard restore for reliability.")
                try executor.typeText(text)
                return successResult(callID: functionCall.callID, stepDescription: "Type text '\(text)'")
            case "key":
                guard let raw = firstStringValue(from: object, keys: ["key", "text", "keys"]),
                      let shortcut = parseShortcut(raw) else {
                    return invalidInputResult(callID: functionCall.callID, action: action)
                }
                if let policyViolationMessage = validateDesktopShortcutPolicy(rawShortcut: raw, shortcut: shortcut) {
                    return ToolExecutionResult(
                        callID: functionCall.callID,
                        output: makeToolOutput(ok: false, message: policyViolationMessage, error: "policy_violation"),
                        isError: true,
                        stepDescription: nil,
                        generatedQuestions: []
                    )
                }
                if shouldPrimeDisplayFocusBeforeShortcut(shortcut) {
                    anchorInteractionTarget(executor: executor, reason: "key_shortcut_focus_prime", performClick: true)
                    await sleepNanoseconds(140_000_000)
                }
                try executor.sendShortcut(
                    key: shortcut.key,
                    command: shortcut.command,
                    option: shortcut.option,
                    control: shortcut.control,
                    shift: shortcut.shift
                )
                return successResult(callID: functionCall.callID, stepDescription: "Press shortcut '\(raw)'")
            case "open_app":
                guard let appName = firstStringValue(from: object, keys: ["app", "name"]) else {
                    return invalidInputResult(callID: functionCall.callID, action: action)
                }
                anchorInteractionTarget(executor: executor, reason: "open_app", performClick: true)
                await sleepNanoseconds(180_000_000)
                try executor.openApp(named: appName)
                return successResult(callID: functionCall.callID, stepDescription: "Open app '\(appName)'")
            case "open_url":
                guard let urlRaw = firstStringValue(from: object, keys: ["url"]),
                      let url = URL(string: urlRaw) else {
                    return invalidInputResult(callID: functionCall.callID, action: action)
                }
                anchorInteractionTarget(executor: executor, reason: "open_url", performClick: true)
                await sleepNanoseconds(180_000_000)
                try executor.openURL(url)
                return successResult(callID: functionCall.callID, stepDescription: "Open URL '\(url.absoluteString)'")
            case "scroll":
                if let (x, y) = extractPoint(from: object) {
                    let mapped = mapToScreenCoordinates(x: x, y: y)
                    try executor.moveMouse(x: mapped.x, y: mapped.y)
                }
                guard let (dx, dy) = extractScrollDelta(from: object) else {
                    return invalidInputResult(callID: functionCall.callID, action: action)
                }
                try executor.scroll(deltaX: dx, deltaY: dy)
                return successResult(callID: functionCall.callID, stepDescription: "Scroll (\(dx), \(dy))")
            case "wait":
                let seconds = max(0.1, object["seconds"]?.doubleValue ?? object["duration"]?.doubleValue ?? 0.5)
                await sleepNanoseconds(UInt64(seconds * 1_000_000_000))
                return successResult(callID: functionCall.callID, stepDescription: "Wait \(String(format: "%.1f", seconds))s")
            default:
                return ToolExecutionResult(
                    callID: functionCall.callID,
                    output: makeToolOutput(
                        ok: false,
                        message: "Unsupported action '\(action)'.",
                        error: "unsupported_action"
                    ),
                    isError: true,
                    stepDescription: nil,
                    generatedQuestions: ["Action '\(action)' is unsupported. What should I do instead?"]
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return ToolExecutionResult(
                callID: functionCall.callID,
                output: makeToolOutput(
                    ok: false,
                    message: "Action '\(action)' failed: \(error.localizedDescription)",
                    error: "execution_failed"
                ),
                isError: true,
                stepDescription: nil,
                generatedQuestions: ["Execution failed for action '\(action)'. What should I do instead?"]
            )
        }
    }

    func successResult(callID: String, stepDescription: String) -> ToolExecutionResult {
        ToolExecutionResult(
            callID: callID,
            output: makeToolOutput(ok: true, message: "Done"),
            isError: false,
            stepDescription: stepDescription,
            generatedQuestions: []
        )
    }

    func invalidInputResult(callID: String, action: String) -> ToolExecutionResult {
        ToolExecutionResult(
            callID: callID,
            output: makeToolOutput(
                ok: false,
                message: "Action '\(action)' had invalid input.",
                error: "invalid_input"
            ),
            isError: true,
            stepDescription: nil,
            generatedQuestions: ["Action '\(action)' had invalid input from the model. How should I proceed?"]
        )
    }

    func executeTerminalExecFunctionCall(
        callID: String,
        input: [String: OpenAIJSONValue],
        executor: any DesktopActionExecutor
    ) async -> ToolExecutionResult {
        guard let executableRaw = input["executable"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !executableRaw.isEmpty else {
            return ToolExecutionResult(
                callID: callID,
                output: makeToolOutput(ok: false, message: "Terminal tool input missing 'executable'.", error: "invalid_input"),
                isError: true,
                stepDescription: nil,
                generatedQuestions: ["Model omitted the terminal executable to run. What should I do?"]
            )
        }

        var args: [String] = []
        if let argsValue = input["args"] {
            guard let array = argsValue.arrayValue else {
                return ToolExecutionResult(
                    callID: callID,
                    output: makeToolOutput(ok: false, message: "Terminal tool input field 'args' must be an array of strings.", error: "invalid_input"),
                    isError: true,
                    stepDescription: nil,
                    generatedQuestions: ["Terminal tool input field 'args' was invalid. What should I do?"]
                )
            }
            for value in array {
                guard let s = value.stringValue else {
                    return ToolExecutionResult(
                        callID: callID,
                        output: makeToolOutput(ok: false, message: "Terminal tool input field 'args' must contain only strings.", error: "invalid_input"),
                        isError: true,
                        stepDescription: nil,
                        generatedQuestions: ["Terminal tool input field 'args' was invalid. What should I do?"]
                    )
                }
                args.append(s)
            }
        }

        let timeoutRaw = input["timeout_seconds"]?.doubleValue ?? Self.terminalExecDefaultTimeoutSeconds
        let timeoutSeconds = min(Self.terminalExecMaxTimeoutSeconds, max(0.1, timeoutRaw))

        if let policyViolationMessage = validateTerminalExecPolicy(executable: executableRaw, args: args) {
            return ToolExecutionResult(
                callID: callID,
                output: makeToolOutput(ok: false, message: policyViolationMessage, error: "policy_violation"),
                isError: true,
                stepDescription: nil,
                generatedQuestions: []
            )
        }

        guard let resolvedExecutable = resolveTerminalExecutable(executableRaw) else {
            return ToolExecutionResult(
                callID: callID,
                output: makeToolOutput(
                    ok: false,
                    message: "Executable '\(executableRaw)' was not found or is not executable.",
                    error: "executable_not_found"
                ),
                isError: true,
                stepDescription: nil,
                generatedQuestions: ["Terminal command executable was not found ('\(executableRaw)'). What should I do instead?"]
            )
        }

        let commandSummary = summarizeTerminalCommand(executablePath: resolvedExecutable, args: args)
        recordTrace(kind: .info, "Terminal exec requested: \(commandSummary)")
        // Keep pointer anchored to selected display before terminal side-effects (for example app/process activation).
        anchorInteractionTarget(executor: executor, reason: "terminal_exec", performClick: false)

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
                callID: callID,
                output: payloadText,
                isError: !payload.ok,
                stepDescription: "Terminal exec: \(commandSummary)",
                generatedQuestions: payload.ok ? [] : ["Terminal command failed (\(commandSummary)). What should I do instead?"]
            )
        } catch {
            return ToolExecutionResult(
                callID: callID,
                output: makeToolOutput(ok: false, message: "Terminal exec failed: \(error.localizedDescription)", error: "execution_failed"),
                isError: true,
                stepDescription: nil,
                generatedQuestions: ["Terminal exec failed for (\(commandSummary)). What should I do instead?"]
            )
        }
    }

    func resolveTerminalExecutable(_ raw: String) -> String? {
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

    func validateTerminalExecPolicy(executable: String, args: [String]) -> String? {
        let executableName = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
        let commandLineLower = ([executableName] + args).joined(separator: " ").lowercased()

        if Self.terminalExecAlwaysVisualExecutables.contains(executableName) {
            return "Terminal command '\(executableName)' is blocked for UI/visual automation. Use tool 'desktop_action' for on-screen actions (find/hover/click/scroll/type based on screenshots)."
        }

        if Self.terminalExecVisualCommandKeywords.contains(where: { commandLineLower.contains($0) }) {
            return "Terminal command appears to target visual UI state. Use tool 'desktop_action' for on-screen actions and coordinates."
        }

        return nil
    }

    func summarizeTerminalCommand(executablePath: String, args: [String]) -> String {
        let cmd = ([URL(fileURLWithPath: executablePath).lastPathComponent] + args).joined(separator: " ")
        return truncate(cmd, limit: 220)
    }

    func validateDesktopShortcutPolicy(
        rawShortcut: String,
        shortcut: (key: String, command: Bool, option: Bool, control: Bool, shift: Bool)
    ) -> String? {
        let normalizedKey = shortcut.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if shortcut.command && normalizedKey == "tab" {
            return "Shortcut '\(rawShortcut)' is blocked for display stability. Do not use app switcher (cmd+tab). Use action 'open_app' instead."
        }
        return nil
    }

    func shouldPrimeDisplayFocusBeforeShortcut(
        _ shortcut: (key: String, command: Bool, option: Bool, control: Bool, shift: Bool)
    ) -> Bool {
        if shortcut.key == " " {
            return shortcut.command && !shortcut.option && !shortcut.control
        }

        let key = shortcut.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Spotlight is global and can appear on whichever display currently owns focus.
        // Prime focus on the selected run display first.
        return shortcut.command && !shortcut.option && !shortcut.control && (key == "space" || key == "spacebar")
    }

    func runTerminalCommand(
        executablePath: String,
        args: [String],
        timeoutSeconds: Double
    ) async throws -> TerminalCommandExecutionResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let result = try self.runTerminalCommandSync(
                        executablePath: executablePath,
                        args: args,
                        timeoutSeconds: timeoutSeconds
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func runTerminalCommandSync(
        executablePath: String,
        args: [String],
        timeoutSeconds: Double
    ) throws -> TerminalCommandExecutionResult {
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

    func firstStringValue(from object: [String: OpenAIJSONValue], keys: [String]) -> String? {
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

    func parseShortcut(_ raw: String) -> (key: String, command: Bool, option: Bool, control: Bool, shift: Bool)? {
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

    func extractScrollDelta(from object: [String: OpenAIJSONValue]) -> (Int, Int)? {
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

    func extractPoint(from object: [String: OpenAIJSONValue]) -> (Int, Int)? {
        if let x = object["x"]?.intValue, let y = object["y"]?.intValue {
            return (x, y)
        }

        for key in ["coordinate", "coordinates", "position", "point", "location", "pos"] {
            guard let value = object[key] else { continue }
            if let point = extractPoint(from: value) {
                return point
            }
        }

        return nil
    }

    func extractPoint(from value: OpenAIJSONValue) -> (Int, Int)? {
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

    func makeToolOutput(ok: Bool, message: String, data: [String: Any] = [:], error: String? = nil) -> String {
        var payload: [String: Any] = [
            "ok": ok,
            "message": message
        ]
        for (key, value) in data {
            payload[key] = value
        }
        if let error {
            payload["error"] = error
        }

        guard let encoded = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: encoded, encoding: .utf8) else {
            return "{\"ok\":false,\"message\":\"Failed to encode tool output.\",\"error\":\"encode_failed\"}"
        }
        return string
    }

    func functionCallOutputInput(callID: String, output: String) -> [String: Any] {
        [
            "type": "function_call_output",
            "call_id": callID,
            "output": output
        ]
    }

    func desktopActionToolDefinition() -> [String: Any] {
        [
            "type": "function",
            "name": "desktop_action",
            "description": "Execute one desktop action on macOS. Use this tool for click, type, key shortcuts, scrolling, app launching, URL opening, waiting, screenshots, and cursor-position reads.",
            "parameters": [
                "type": "object",
                "properties": [
                    "action": [
                        "type": "string",
                        "enum": [
                            "screenshot",
                            "cursor_position",
                            "get_cursor_position",
                            "mouse_position",
                            "mouse_move",
                            "move_mouse",
                            "move",
                            "left_click",
                            "right_click",
                            "double_click",
                            "type",
                            "key",
                            "open_app",
                            "open_url",
                            "scroll",
                            "wait"
                        ]
                    ],
                    "x": ["type": "integer"],
                    "y": ["type": "integer"],
                    "coordinate": [
                        "oneOf": [
                            [
                                "type": "array",
                                "items": ["type": "integer"],
                                "minItems": 2,
                                "maxItems": 2
                            ],
                            [
                                "type": "object",
                                "properties": [
                                    "x": ["type": "integer"],
                                    "y": ["type": "integer"],
                                    "left": ["type": "integer"],
                                    "top": ["type": "integer"]
                                ],
                                "additionalProperties": true
                            ]
                        ]
                    ],
                    "text": ["type": "string"],
                    "key": ["type": "string"],
                    "keys": ["type": "string"],
                    "app": ["type": "string"],
                    "name": ["type": "string"],
                    "url": ["type": "string"],
                    "delta_x": ["type": "integer"],
                    "delta_y": ["type": "integer"],
                    "scroll_x": ["type": "integer"],
                    "scroll_y": ["type": "integer"],
                    "direction": ["type": "string"],
                    "amount": ["type": "number"],
                    "pixels": ["type": "number"],
                    "seconds": ["type": "number"],
                    "duration": ["type": "number"]
                ],
                "required": ["action"],
                "additionalProperties": true
            ]
        ]
    }

    func terminalExecToolDefinition() -> [String: Any] {
        [
            "type": "function",
            "name": "terminal_exec",
            "description": "Execute a terminal command and return stdout/stderr/exit_code. Use this only for deterministic non-visual command-line tasks.",
            "parameters": [
                "type": "object",
                "properties": [
                    "executable": [
                        "type": "string",
                        "description": "Executable name (resolved from PATH) or absolute path."
                    ],
                    "args": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Argument list."
                    ],
                    "timeout_seconds": [
                        "type": "number",
                        "description": "Optional timeout in seconds (default 30)."
                    ]
                ],
                "required": ["executable"],
                "additionalProperties": false
            ]
        ]
    }
}
