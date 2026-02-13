import Foundation
import CoreGraphics
import AVFoundation
import CoreAudio
import Darwin

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
    private static let outputFinalizeWaitSeconds: TimeInterval = 2.0

    private var process: Process?
    private var standardErrorPipe: Pipe?
    private var standardOutputPipe: Pipe?
    private var outputURL: URL?
    private var currentArguments: [String] = []
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

        switch audioInput {
        case .none:
            return
        case .device(let requestedDeviceID):
            do {
                let run = try launchCapture(outputURL: outputURL, displayID: displayID, audioInput: .device(requestedDeviceID))
                process = run.process
                standardErrorPipe = run.stderrPipe
                standardOutputPipe = run.stdoutPipe
                self.outputURL = outputURL
                lastCaptureIncludesMicrophone = true
                return
            } catch RecordingCaptureError.failedToStart(let withMicReason) {
                let micError = withMicReason.isEmpty ? "unknown microphone capture error" : withMicReason
                do {
                    let run = try launchCapture(outputURL: outputURL, displayID: displayID, audioInput: .systemDefault)
                    process = run.process
                    standardErrorPipe = run.stderrPipe
                    standardOutputPipe = run.stdoutPipe
                    self.outputURL = outputURL
                    lastCaptureIncludesMicrophone = true
                    lastCaptureStartWarning = "Selected microphone device ID \(requestedDeviceID) was unavailable. Fell back to System Default Microphone."
                    return
                } catch RecordingCaptureError.failedToStart(let defaultReason) {
                    let defaultMicError = defaultReason.isEmpty ? "unknown default-microphone error" : defaultReason
                    do {
                        let run = try launchCapture(outputURL: outputURL, displayID: displayID, includeMicrophone: false)
                        process = run.process
                        standardErrorPipe = run.stderrPipe
                        standardOutputPipe = run.stdoutPipe
                        self.outputURL = outputURL
                        lastCaptureIncludesMicrophone = false
                        lastCaptureStartWarning = "Selected microphone failed (\(micError)). Default microphone also failed (\(defaultMicError))."
                        return
                    } catch RecordingCaptureError.failedToStart(let noMicReason) {
                        let fallback = noMicReason.isEmpty ? "unknown non-microphone capture error" : noMicReason
                        throw RecordingCaptureError.failedToStart("Selected mic failed (\(micError)). Default mic failed (\(defaultMicError)). Fallback failed (\(fallback)).")
                    }
                }
            }
        case .systemDefault:
            do {
                let run = try launchCapture(outputURL: outputURL, displayID: displayID, audioInput: .systemDefault)
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
            }
        }
    }

    func stopCapture() throws {
        guard let process else {
            throw RecordingCaptureError.notCapturing
        }

        if process.isRunning {
            // For screencapture -v, interrupt is the normal stop signal for recording finalization.
            process.interrupt()
            Thread.sleep(forTimeInterval: 0.2)
            if process.isRunning {
                process.terminate()
                Thread.sleep(forTimeInterval: 0.2)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
        }
        defer {
            self.process = nil
            standardErrorPipe = nil
            standardOutputPipe = nil
            outputURL = nil
            currentArguments = []
        }

        let stderrReason = readPipe(standardErrorPipe).trimmingCharacters(in: .whitespacesAndNewlines)
        let stdoutReason = readPipe(standardOutputPipe).trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = [stderrReason, stdoutReason]
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
        if let outputURL {
            let size = waitForOutputSize(url: outputURL, timeout: Self.outputFinalizeWaitSeconds + 3.0)
            guard size > 0 else {
                let argText = currentArguments.joined(separator: " ")
                let fallback = "Capture ended but no recording file was created (status \(process.terminationStatus)). Command: screencapture \(argText)"
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
            args.append(contentsOf: ["-G", String(deviceID)])
        }
        args.append(contentsOf: ["-D", String(displayID), outputURL.path])
        currentArguments = args
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
