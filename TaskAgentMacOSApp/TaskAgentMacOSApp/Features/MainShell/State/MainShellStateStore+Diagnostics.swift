import Foundation
import AppKit

extension MainShellStateStore {
    // MARK: - Diagnostics

    func clearLLMCallLog() {
        llmCallRecorder.clear()
        llmCallLog = []
    }

    func clearExecutionTrace() {
        executionTraceRecorder.clear()
        executionTrace = []
    }

    @MainActor
    func copyExecutionTraceToPasteboard(onlyToolUse: Bool) {
        let entries = onlyToolUse ? executionTrace.filter { $0.kind == .toolUse } : executionTrace
        guard !entries.isEmpty else {
            diagnosticTraceStatusMessage = "No trace entries to copy."
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let lines = entries.map { entry in
            "\(formatter.string(from: entry.timestamp)) \(entry.kind.rawValue.uppercased()): \(entry.message)"
        }
        let output = lines.joined(separator: "\n")

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(output, forType: .string)
        diagnosticTraceStatusMessage = "Copied \(entries.count) trace line(s) to clipboard."
    }

    @MainActor
    func copyLLMCallLogToPasteboard(onlyFailures: Bool) {
        let entries = onlyFailures ? llmCallLog.filter { $0.outcome == .failure } : llmCallLog
        guard !entries.isEmpty else {
            diagnosticTraceStatusMessage = "No LLM call entries to copy."
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var lines: [String] = []
        for entry in entries {
            var header = "\(formatter.string(from: entry.finishedAt)) \(entry.outcome == .success ? "OK" : "FAIL") \(entry.provider.rawValue)/\(entry.operation.rawValue) #\(entry.attempt)"
            if let status = entry.httpStatus {
                header += " HTTP \(status)"
            }
            header += " \(entry.durationMs)ms"

            lines.append(header)
            lines.append("  url: \(entry.url)")
            if let requestId = entry.requestId, !requestId.isEmpty {
                lines.append("  request-id: \(requestId)")
            }
            if let bytesSent = entry.bytesSent {
                lines.append("  bytes-sent: \(bytesSent)")
            }
            if let bytesReceived = entry.bytesReceived {
                lines.append("  bytes-received: \(bytesReceived)")
            }
            if let message = entry.message, !message.isEmpty {
                lines.append("  message: \(message)")
            }
            lines.append("")
        }

        let output = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(output, forType: .string)
        diagnosticTraceStatusMessage = "Copied \(entries.count) LLM call(s) to clipboard."
    }

    @MainActor
    func copyAllDiagnosticsToPasteboard(onlyToolUseTrace: Bool, onlyLLMFailures: Bool) {
        let traceEntries = onlyToolUseTrace ? executionTrace.filter { $0.kind == .toolUse } : executionTrace
        let llmEntries = onlyLLMFailures ? llmCallLog.filter { $0.outcome == .failure } : llmCallLog

        guard !traceEntries.isEmpty || !llmEntries.isEmpty else {
            diagnosticTraceStatusMessage = "No diagnostics to copy."
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var lines: [String] = []

        if !traceEntries.isEmpty {
            lines.append("=== EXECUTION TRACE ===")
            lines.append(contentsOf: traceEntries.map { entry in
                "\(formatter.string(from: entry.timestamp)) \(entry.kind.rawValue.uppercased()): \(entry.message)"
            })
            lines.append("")
        }

        if !llmEntries.isEmpty {
            lines.append("=== LLM CALLS ===")
            for entry in llmEntries {
                var header = "\(formatter.string(from: entry.finishedAt)) \(entry.outcome == .success ? "OK" : "FAIL") \(entry.provider.rawValue)/\(entry.operation.rawValue) #\(entry.attempt)"
                if let status = entry.httpStatus {
                    header += " HTTP \(status)"
                }
                header += " \(entry.durationMs)ms"
                lines.append(header)
                lines.append("  url: \(entry.url)")
                if let requestId = entry.requestId, !requestId.isEmpty {
                    lines.append("  request-id: \(requestId)")
                }
                if let message = entry.message, !message.isEmpty {
                    lines.append("  message: \(message)")
                }
                lines.append("")
            }
        }

        let output = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(output, forType: .string)
        diagnosticTraceStatusMessage = "Copied diagnostics to clipboard."
    }

    @MainActor
    func captureDiagnosticScreenshot() async {
        guard !isCapturingDiagnosticScreenshot else {
            return
        }

        isCapturingDiagnosticScreenshot = true
        diagnosticScreenshotStatusMessage = "Capturing screenshot..."

        do {
            let capture = try await Task.detached {
                try DesktopScreenshotService.captureMainDisplayPNG()
            }.value

            lastDiagnosticScreenshotPNGData = capture.pngData
            lastDiagnosticScreenshotWidth = capture.width
            lastDiagnosticScreenshotHeight = capture.height
            diagnosticScreenshotStatusMessage = "Captured \(capture.width)x\(capture.height) (\(capture.pngData.count) bytes)."
        } catch DesktopScreenshotServiceError.captureFailed {
            diagnosticScreenshotStatusMessage = "Screenshot capture failed. Ensure Screen Recording permission is granted."
        } catch DesktopScreenshotServiceError.decodeFailed {
            diagnosticScreenshotStatusMessage = "Screenshot captured but failed to decode image."
        } catch {
            diagnosticScreenshotStatusMessage = "Screenshot capture failed: \(error.localizedDescription)"
        }

        isCapturingDiagnosticScreenshot = false
    }
}
