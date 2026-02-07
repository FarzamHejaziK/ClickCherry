import Foundation
import CoreGraphics
import AVFoundation

struct CaptureDisplayOption: Identifiable, Equatable {
    let id: Int
    let label: String
}

enum RecordingCaptureError: Error {
    case alreadyCapturing
    case notCapturing
    case permissionDenied
    case failedToStart(String)
    case failedToStop(String)
}

protocol RecordingCaptureService {
    var isCapturing: Bool { get }
    var lastCaptureIncludesMicrophone: Bool { get }
    var lastCaptureStartWarning: String? { get }
    func listDisplays() -> [CaptureDisplayOption]
    func startCapture(outputURL: URL, displayID: Int) throws
    func stopCapture() throws
}

final class ShellRecordingCaptureService: RecordingCaptureService {
    private static let startupGracePeriodNanoseconds: UInt64 = 250_000_000
    private static let outputFinalizeWaitSeconds: TimeInterval = 2.0

    private var process: Process?
    private var standardErrorPipe: Pipe?
    private var standardOutputPipe: Pipe?
    private var outputURL: URL?
    private(set) var lastCaptureIncludesMicrophone: Bool = false
    private(set) var lastCaptureStartWarning: String?

    var isCapturing: Bool {
        process?.isRunning ?? false
    }

    func listDisplays() -> [CaptureDisplayOption] {
        let count = activeDisplayCount()
        guard count > 0 else {
            return [CaptureDisplayOption(id: 1, label: "Display 1")]
        }
        return (1...count).map { CaptureDisplayOption(id: $0, label: "Display \($0)") }
    }

    func startCapture(outputURL: URL, displayID: Int) throws {
        guard !isCapturing else {
            throw RecordingCaptureError.alreadyCapturing
        }
        lastCaptureIncludesMicrophone = false
        lastCaptureStartWarning = nil

        if !CGPreflightScreenCaptureAccess() {
            let granted = CGRequestScreenCaptureAccess()
            guard granted else {
                throw RecordingCaptureError.permissionDenied
            }
        }

        let parentDir = outputURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        let microphoneAllowed = requestMicrophoneAccessIfNeeded()
        if !microphoneAllowed {
            let run = try launchCapture(outputURL: outputURL, displayID: displayID, includeMicrophone: false)
            process = run.process
            standardErrorPipe = run.stderrPipe
            standardOutputPipe = run.stdoutPipe
            self.outputURL = outputURL
            lastCaptureIncludesMicrophone = false
            lastCaptureStartWarning = "Microphone permission is not granted for TaskAgentMacOSApp. Enable it in Privacy & Security > Microphone."
            return
        }

        do {
            let run = try launchCapture(outputURL: outputURL, displayID: displayID, includeMicrophone: true)
            process = run.process
            standardErrorPipe = run.stderrPipe
            standardOutputPipe = run.stdoutPipe
            self.outputURL = outputURL
            lastCaptureIncludesMicrophone = true
            return
        } catch RecordingCaptureError.failedToStart(let withMicReason) {
            let micError = withMicReason.isEmpty ? "unknown microphone capture error" : withMicReason
            do {
                let run = try launchCapture(outputURL: outputURL, displayID: displayID, includeMicrophone: false)
                process = run.process
                standardErrorPipe = run.stderrPipe
                standardOutputPipe = run.stdoutPipe
                self.outputURL = outputURL
                lastCaptureIncludesMicrophone = false
                lastCaptureStartWarning = "Microphone capture unavailable for this app run: \(micError)"
                return
            } catch RecordingCaptureError.failedToStart(let noMicReason) {
                let fallback = noMicReason.isEmpty ? "unknown non-microphone capture error" : noMicReason
                throw RecordingCaptureError.failedToStart("Mic mode failed (\(micError)). Fallback failed (\(fallback)).")
            }
        } catch let error as RecordingCaptureError {
            throw error
        } catch {
            throw RecordingCaptureError.failedToStart(error.localizedDescription)
        }
    }

    func stopCapture() throws {
        guard let process else {
            throw RecordingCaptureError.notCapturing
        }

        if process.isRunning {
            process.interrupt()
            process.waitUntilExit()
        }
        defer {
            self.process = nil
            standardErrorPipe = nil
            standardOutputPipe = nil
            outputURL = nil
        }

        let reason = readPipe(standardErrorPipe).trimmingCharacters(in: .whitespacesAndNewlines)
        if let outputURL {
            let size = waitForOutputSize(url: outputURL, timeout: Self.outputFinalizeWaitSeconds)
            guard size > 0 else {
                let fallback = "Capture ended but no recording file was created (status \(process.terminationStatus))."
                throw RecordingCaptureError.failedToStop(reason.isEmpty ? fallback : reason)
            }
        } else {
            throw RecordingCaptureError.failedToStop("Capture ended without a valid output file path.")
        }
    }

    private func activeDisplayCount() -> Int {
        var count: UInt32 = 0
        let result = CGGetActiveDisplayList(0, nil, &count)
        guard result == .success else {
            return 0
        }
        return Int(count)
    }

    private func readPipe(_ pipe: Pipe?) -> String {
        guard let pipe else {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else {
            return ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func waitForOutputSize(url: URL, timeout: TimeInterval) -> Int64 {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            if size > 0 {
                return size
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func requestMicrophoneAccessIfNeeded() -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            var granted = false
            let semaphore = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .audio) { allowed in
                granted = allowed
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 30)
            return granted
        @unknown default:
            return false
        }
    }

    private func launchCapture(outputURL: URL, displayID: Int, includeMicrophone: Bool) throws -> (process: Process, stderrPipe: Pipe, stdoutPipe: Pipe) {
        let captureProcess = Process()
        captureProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")

        var args = ["-v"]
        if includeMicrophone {
            args.append("-g")
        }
        args.append(contentsOf: ["-D", String(displayID), outputURL.path])
        captureProcess.arguments = args

        let stderrPipe = Pipe()
        let stdoutPipe = Pipe()
        captureProcess.standardError = stderrPipe
        captureProcess.standardOutput = stdoutPipe

        do {
            try captureProcess.run()
            Thread.sleep(forTimeInterval: TimeInterval(Self.startupGracePeriodNanoseconds) / 1_000_000_000)
            if !captureProcess.isRunning {
                captureProcess.waitUntilExit()
                let reason = readPipe(stderrPipe).trimmingCharacters(in: .whitespacesAndNewlines)
                let fallback = "screencapture exited with status \(captureProcess.terminationStatus) before capture started."
                throw RecordingCaptureError.failedToStart(reason.isEmpty ? fallback : reason)
            }
            return (captureProcess, stderrPipe, stdoutPipe)
        } catch let error as RecordingCaptureError {
            throw error
        } catch {
            throw RecordingCaptureError.failedToStart(error.localizedDescription)
        }
    }
}
