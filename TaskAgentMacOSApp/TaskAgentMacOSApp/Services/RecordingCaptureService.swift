import Foundation
import CoreGraphics

enum RecordingCaptureError: Error {
    case alreadyCapturing
    case notCapturing
    case permissionDenied
    case failedToStart
}

protocol RecordingCaptureService {
    var isCapturing: Bool { get }
    func startCapture(outputURL: URL) throws
    func stopCapture() throws
}

final class ShellRecordingCaptureService: RecordingCaptureService {
    private var process: Process?

    var isCapturing: Bool {
        process?.isRunning ?? false
    }

    func startCapture(outputURL: URL) throws {
        guard !isCapturing else {
            throw RecordingCaptureError.alreadyCapturing
        }

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

        let captureProcess = Process()
        captureProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        captureProcess.arguments = ["-v", outputURL.path]

        do {
            try captureProcess.run()
            process = captureProcess
        } catch {
            throw RecordingCaptureError.failedToStart
        }
    }

    func stopCapture() throws {
        guard let process, process.isRunning else {
            throw RecordingCaptureError.notCapturing
        }

        process.terminate()
        self.process = nil
    }
}
