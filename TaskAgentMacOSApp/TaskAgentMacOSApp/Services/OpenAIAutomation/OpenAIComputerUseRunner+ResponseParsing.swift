import Foundation

extension OpenAIComputerUseRunner {
    func extractFunctionCalls(from response: OpenAIResponsesResponse) throws -> [ParsedFunctionCall] {
        guard let output = response.output else { return [] }

        var calls: [ParsedFunctionCall] = []
        for item in output where item.type == "function_call" {
            guard let callID = (item.callID ?? item.id)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !callID.isEmpty else {
                throw OpenAIExecutionPlannerError.invalidToolLoopResponse
            }
            guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                throw OpenAIExecutionPlannerError.invalidToolLoopResponse
            }
            guard let arguments = item.arguments?.jsonString(using: jsonEncoder) else {
                throw OpenAIExecutionPlannerError.invalidToolLoopResponse
            }
            calls.append(ParsedFunctionCall(callID: callID, name: name, arguments: arguments))
        }
        return calls
    }

    func extractCompletionText(from response: OpenAIResponsesResponse) -> String {
        if let topLevel = response.outputText?.trimmingCharacters(in: .whitespacesAndNewlines), !topLevel.isEmpty {
            return topLevel
        }

        var parts: [String] = []
        for item in response.output ?? [] {
            if item.type == "message" {
                for content in item.content ?? [] {
                    guard content.type == "output_text" || content.type == "text" else { continue }
                    if let text = content.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                        parts.append(text)
                    }
                }
            } else if item.type == "output_text" || item.type == "text" {
                if let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    parts.append(text)
                }
            }
        }

        return parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func parseCompletion(from text: String) -> CompletionResult {
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
           let payload = try? jsonDecoder.decode(OpenAIToolLoopCompletionPayload.self, from: payloadData) {
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

    func extractJSONPayloadData(from content: String) -> Data? {
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

    func mapStatus(_ raw: String) -> AutomationRunOutcome {
        switch raw.uppercased() {
        case "SUCCESS":
            return .success
        case "FAILED":
            return .failed
        default:
            return .needsClarification
        }
    }

    func dedupe(_ questions: [String]) -> [String] {
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

    func summarizeResponse(turn: Int, response: OpenAIResponsesResponse) -> String {
        if let output = response.output {
            let calls = output.filter { $0.type == "function_call" }
            if !calls.isEmpty {
                let summary = calls.map { call in
                    summarizeFunctionCall(
                        ParsedFunctionCall(
                            callID: call.callID ?? call.id ?? "unknown",
                            name: call.name ?? "unknown",
                            arguments: call.arguments?.jsonString(using: jsonEncoder) ?? "{}"
                        )
                    )
                }.joined(separator: " | ")
                return "Turn \(turn): function_call x\(calls.count): \(summary)"
            }
        }

        let text = extractCompletionText(from: response)
        if !text.isEmpty {
            return "Turn \(turn): text: \(truncate(text, limit: 400))"
        }

        if let output = response.output, !output.isEmpty {
            let types = output.map(\.type).joined(separator: ",")
            return "Turn \(turn): no function_call; output types: \(types)"
        }
        return "Turn \(turn): empty output."
    }

    func summarizeFunctionCall(_ functionCall: ParsedFunctionCall) -> String {
        guard
            let data = functionCall.arguments.data(using: .utf8),
            let object = try? jsonDecoder.decode([String: OpenAIJSONValue].self, from: data)
        else {
            return "\(functionCall.name)(invalid_arguments)"
        }

        if functionCall.name.lowercased() == "terminal_exec" {
            let executable = firstStringValue(from: object, keys: ["executable"]) ?? ""
            let args: [String]
            if let array = object["args"]?.arrayValue {
                args = array.compactMap(\.stringValue)
            } else {
                args = []
            }
            let argsPreview = args.prefix(6).joined(separator: " ")
            let suffix = args.count > 6 ? " ..." : ""
            return "terminal_exec(executable=\"\(truncate(executable, limit: 80))\", args=\"\(truncate(argsPreview + suffix, limit: 160))\")"
        }

        let action = (object["action"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if action.isEmpty {
            return "\(functionCall.name)(missing_action)"
        }

        switch action.lowercased() {
        case "mouse_move", "move_mouse", "move", "left_click", "double_click", "right_click":
            let point = extractPoint(from: object)
            let xText = point.map { String($0.0) } ?? "?"
            let yText = point.map { String($0.1) } ?? "?"
            return "\(functionCall.name).\(action)(x=\(xText),y=\(yText))"
        case "scroll":
            if let (dx, dy) = extractScrollDelta(from: object) {
                return "\(functionCall.name).scroll(dx=\(dx),dy=\(dy))"
            }
            return "\(functionCall.name).scroll"
        case "type":
            let text = object["text"]?.stringValue ?? ""
            return "\(functionCall.name).type(text=\"\(truncate(text, limit: 80))\")"
        case "key":
            let raw = firstStringValue(from: object, keys: ["key", "text", "keys"]) ?? ""
            return "\(functionCall.name).key(\"\(truncate(raw, limit: 80))\")"
        case "open_app":
            let app = firstStringValue(from: object, keys: ["app", "name"]) ?? ""
            return "\(functionCall.name).open_app(\"\(truncate(app, limit: 80))\")"
        case "open_url":
            let url = firstStringValue(from: object, keys: ["url"]) ?? ""
            return "\(functionCall.name).open_url(\"\(truncate(url, limit: 140))\")"
        case "wait":
            let seconds = object["seconds"]?.doubleValue ?? object["duration"]?.doubleValue
            if let seconds {
                return "\(functionCall.name).wait(\(String(format: "%.1f", seconds))s)"
            }
            return "\(functionCall.name).wait"
        case "cursor_position", "get_cursor_position", "mouse_position":
            return "\(functionCall.name).cursor_position"
        case "screenshot":
            return "\(functionCall.name).screenshot"
        default:
            return "\(functionCall.name).\(action)"
        }
    }

    func recordTrace(kind: ExecutionTraceKind, _ message: String) {
        traceSink?(ExecutionTraceEntry(kind: kind, message: truncate(message, limit: 900)))
    }

    func truncate(_ message: String, limit: Int) -> String {
        let cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > limit else {
            return cleaned
        }
        let prefix = cleaned.prefix(limit)
        return "\(prefix)..."
    }
}
