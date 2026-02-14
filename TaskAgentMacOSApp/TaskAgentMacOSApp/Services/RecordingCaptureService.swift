import Foundation
import CoreGraphics
import AVFoundation
import CoreAudio
import Darwin
import AppKit

struct CaptureDisplayOption: Identifiable, Equatable {
    let id: Int
    let label: String
}

enum CaptureAudioInputMode: Equatable {
    case none
    case systemDefault
    case device(Int)
}

struct CaptureAudioInputOption: Identifiable, Equatable {
    let id: String
    let label: String
    let mode: CaptureAudioInputMode
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
    func listAudioInputs() -> [CaptureAudioInputOption]
    func startCapture(outputURL: URL, displayID: Int, audioInput: CaptureAudioInputMode) throws
    func stopCapture() throws
}

final class ShellRecordingCaptureService: RecordingCaptureService {
    private static let startupGracePeriodNanoseconds: UInt64 = 250_000_000
    // Finalization can lag process exit, especially on first capture or under load.
    private static let outputFinalizeWaitSeconds: TimeInterval = 6.0
    private static let stopSignalGraceSeconds: TimeInterval = 3.0
    private static let stopTerminateGraceSeconds: TimeInterval = 1.0

    private var process: Process?
    private var standardErrorPipe: Pipe?
    private var standardOutputPipe: Pipe?
    private var standardInputPipe: Pipe?
    private var outputURL: URL?
    private var currentArguments: [String] = []
    private var originalDefaultInputDeviceID: AudioDeviceID?
    private var didOverrideDefaultInputDevice: Bool = false
    private(set) var lastCaptureIncludesMicrophone: Bool = false
    private(set) var lastCaptureStartWarning: String?

    var isCapturing: Bool {
        process?.isRunning ?? false
    }

    func listDisplays() -> [CaptureDisplayOption] {
        let screens = ScreenDisplayIndexService.orderedScreensMainFirst()
        guard !screens.isEmpty else {
            return [CaptureDisplayOption(id: 1, label: "Display 1")]
        }
        return screens.enumerated().map { index, _ in
            CaptureDisplayOption(id: index + 1, label: "Display \(index + 1)")
        }
    }

    func listAudioInputs() -> [CaptureAudioInputOption] {
        let devices = inputAudioDevices()
        var options: [CaptureAudioInputOption] = [
            CaptureAudioInputOption(id: "default", label: "System Default Microphone", mode: .systemDefault)
        ]
        options.append(
            contentsOf: devices.map { device in
                CaptureAudioInputOption(
                    id: "device-\(device.id)",
                    label: "\(device.name) (ID \(device.id))",
                    mode: .device(device.id)
                )
            }
        )
        options.append(CaptureAudioInputOption(id: "none", label: "No Microphone", mode: .none))
        return options
    }

    func startCapture(outputURL: URL, displayID: Int, audioInput: CaptureAudioInputMode) throws {
        guard !isCapturing else {
            throw RecordingCaptureError.alreadyCapturing
        }
        lastCaptureIncludesMicrophone = false
        lastCaptureStartWarning = nil
        originalDefaultInputDeviceID = nil
        didOverrideDefaultInputDevice = false

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

        if audioInput == .none {
            let run = try launchCapture(outputURL: outputURL, displayID: displayID, includeMicrophone: false)
            process = run.process
            standardErrorPipe = run.stderrPipe
            standardOutputPipe = run.stdoutPipe
            self.outputURL = outputURL
            lastCaptureIncludesMicrophone = false
            return
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

        // `screencapture -G<id>` has proven unreliable across devices; in practice it can fail to
        // finalize the recording file. Instead, for explicit device selection we temporarily
        // switch the system default input device and record with `-g` (default input).
        let needsDeviceOverride: AudioDeviceID?
        switch audioInput {
        case .none:
            needsDeviceOverride = nil
        case .systemDefault:
            needsDeviceOverride = nil
        case .device(let requestedDeviceID):
            needsDeviceOverride = AudioDeviceID(requestedDeviceID)
        }

        if let requested = needsDeviceOverride {
            if let currentDefault = getDefaultInputDeviceID() {
                originalDefaultInputDeviceID = currentDefault
                if currentDefault != requested {
                    if setDefaultInputDeviceID(requested) {
                        didOverrideDefaultInputDevice = true
                    } else {
                        lastCaptureStartWarning = "Selected microphone could not be activated; using System Default Microphone."
                    }
                }
            } else {
                lastCaptureStartWarning = "Could not read system default microphone; using System Default Microphone."
            }
        }

        do {
            let run = try launchCapture(outputURL: outputURL, displayID: displayID, audioInput: .systemDefault)
            process = run.process
            standardErrorPipe = run.stderrPipe
            standardOutputPipe = run.stdoutPipe
            self.outputURL = outputURL
            lastCaptureIncludesMicrophone = true
        } catch {
            // If we modified system audio input, restore it before bubbling error/fallback.
            restoreDefaultInputDeviceIfNeeded()
            do {
                let run = try launchCapture(outputURL: outputURL, displayID: displayID, includeMicrophone: false)
                process = run.process
                standardErrorPipe = run.stderrPipe
                standardOutputPipe = run.stdoutPipe
                self.outputURL = outputURL
                lastCaptureIncludesMicrophone = false
                if lastCaptureStartWarning == nil {
                    lastCaptureStartWarning = "Microphone capture unavailable for this app run; recording without microphone audio."
                }
            } catch let error as RecordingCaptureError {
                throw error
            } catch {
                throw RecordingCaptureError.failedToStart(error.localizedDescription)
            }
        }
    }

    func stopCapture() throws {
        guard let process else {
            throw RecordingCaptureError.notCapturing
        }

        if process.isRunning {
            // `screencapture -v` can require "any character" on stdin to stop recording.
            // Provide stdin and send a byte first so it can finalize cleanly.
            if let input = standardInputPipe {
                let data = Data("x\n".utf8)
                input.fileHandleForWriting.write(data)
                // Closing stdin helps some versions of screencapture exit the recording loop.
                try? input.fileHandleForWriting.close()
            }

            // For `screencapture -v`, interrupt (SIGINT) is the normal stop signal for recording finalization.
            // Important: do not immediately SIGTERM the process; doing so can exit without producing a file.
            process.interrupt()

            let sigintDeadline = Date().addingTimeInterval(Self.stopSignalGraceSeconds)
            while process.isRunning, Date() < sigintDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }

            if process.isRunning {
                process.terminate()
                let sigtermDeadline = Date().addingTimeInterval(Self.stopTerminateGraceSeconds)
                while process.isRunning, Date() < sigtermDeadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
            }

            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }

            process.waitUntilExit()
        }
        defer {
            restoreDefaultInputDeviceIfNeeded()
            self.process = nil
            standardErrorPipe = nil
            standardOutputPipe = nil
            standardInputPipe = nil
            outputURL = nil
            currentArguments = []
        }

        let stderrReason = readPipe(standardErrorPipe).trimmingCharacters(in: .whitespacesAndNewlines)
        let stdoutReason = readPipe(standardOutputPipe).trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = [stderrReason, stdoutReason]
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
        if let outputURL {
            let size = waitForOutputSize(url: outputURL, timeout: Self.outputFinalizeWaitSeconds)
            guard size > 0 else {
                let argText = currentArguments.joined(separator: " ")
                let status = process.terminationStatus
                let fallback = "Capture ended but no recording file was created (status \(status)). Command: screencapture \(argText)"
                throw RecordingCaptureError.failedToStop(reason.isEmpty ? fallback : reason)
            }
            if isPNGFile(url: outputURL) {
                throw RecordingCaptureError.failedToStop("Capture output was a still image, not a video. Retry capture and keep Screen Recording enabled for this app.")
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

    // Display ordering is handled by `ScreenDisplayIndexService` to match `screencapture -D`.

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

    private func inputAudioDevices() -> [(id: Int, name: String)] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var propertySize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize) == noErr else {
            return []
        }

        let count = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: AudioDeviceID(0), count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize, &deviceIDs) == noErr else {
            return []
        }

        var results: [(id: Int, name: String)] = []
        for deviceID in deviceIDs {
            guard deviceHasInput(deviceID) else {
                continue
            }
            let name = deviceName(deviceID) ?? "Audio Device"
            results.append((id: Int(deviceID), name: name))
        }
        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func deviceHasInput(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var propertySize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &propertySize) == noErr else {
            return false
        }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(propertySize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListPointer.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, bufferListPointer) == noErr else {
            return false
        }

        let audioBufferList = bufferListPointer.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let channelCount = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
        return channelCount > 0
    }

    private func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        let result = withUnsafeMutableBytes(of: &name) { rawBuffer -> OSStatus in
            guard let baseAddress = rawBuffer.baseAddress else {
                return -1
            }
            return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, baseAddress)
        }
        guard result == noErr else {
            return nil
        }
        return name as String
    }

    private func getDefaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )
        guard status == noErr, deviceID != 0 else {
            return nil
        }
        return deviceID
    }

    private func setDefaultInputDeviceID(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var id = deviceID
        let propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            propertySize,
            &id
        )
        return status == noErr
    }

    private func restoreDefaultInputDeviceIfNeeded() {
        guard didOverrideDefaultInputDevice, let originalDefaultInputDeviceID else {
            originalDefaultInputDeviceID = nil
            didOverrideDefaultInputDevice = false
            return
        }

        _ = setDefaultInputDeviceID(originalDefaultInputDeviceID)
        self.originalDefaultInputDeviceID = nil
        didOverrideDefaultInputDevice = false
    }

    private func isPNGFile(url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? handle.close() }
        guard let bytes = try? handle.read(upToCount: 8), bytes.count == 8 else {
            return false
        }
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        return Array(bytes) == pngSignature
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
        let audioInput: CaptureAudioInputMode = includeMicrophone ? .systemDefault : .none
        return try launchCapture(outputURL: outputURL, displayID: displayID, audioInput: audioInput)
    }

    private func launchCapture(outputURL: URL, displayID: Int, audioInput: CaptureAudioInputMode) throws -> (process: Process, stderrPipe: Pipe, stdoutPipe: Pipe) {
        let captureProcess = Process()
        captureProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")

        var args = ["-v"]
        switch audioInput {
        case .none:
            break
        case .systemDefault:
            args.append("-g")
        case .device(let deviceID):
            // Prefer `-g` and drive explicit selection by temporarily setting system default input.
            args.append("-g")
            lastCaptureStartWarning = "Audio device \(deviceID) capture uses System Default Microphone (device selection is applied via temporary default input)."
        }
        args.append(contentsOf: ["-D", String(displayID), outputURL.path])
        currentArguments = args
        captureProcess.arguments = args

        let stderrPipe = Pipe()
        let stdoutPipe = Pipe()
        let stdinPipe = Pipe()
        captureProcess.standardError = stderrPipe
        captureProcess.standardOutput = stdoutPipe
        captureProcess.standardInput = stdinPipe

        do {
            try captureProcess.run()
            Thread.sleep(forTimeInterval: TimeInterval(Self.startupGracePeriodNanoseconds) / 1_000_000_000)
            if !captureProcess.isRunning {
                captureProcess.waitUntilExit()
                let reason = readPipe(stderrPipe).trimmingCharacters(in: .whitespacesAndNewlines)
                let fallback = "screencapture exited with status \(captureProcess.terminationStatus) before capture started."
                throw RecordingCaptureError.failedToStart(reason.isEmpty ? fallback : reason)
            }
            standardInputPipe = stdinPipe
            return (captureProcess, stderrPipe, stdoutPipe)
        } catch let error as RecordingCaptureError {
            throw error
        } catch {
            throw RecordingCaptureError.failedToStart(error.localizedDescription)
        }
    }
}
