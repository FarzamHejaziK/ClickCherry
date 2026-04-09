import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import Foundation

enum AppPermission: Equatable, Hashable {
    case screenRecording
    case microphone
    case accessibility
    case inputMonitoring
}

enum PermissionGrantStatus: Equatable {
    case unknown
    case granted
    case notGranted

    var label: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .granted:
            return "Granted"
        case .notGranted:
            return "Not Granted"
        }
    }
}

enum PermissionPrimaryAction: Equatable {
    case requestAccess
    case openSettings

    var buttonTitle: String {
        switch self {
        case .requestAccess:
            return "Grant Access"
        case .openSettings:
            return "Open Settings"
        }
    }
}

protocol PermissionService {
    func openSystemSettings(for permission: AppPermission)
    func currentStatus(for permission: AppPermission) -> PermissionGrantStatus
    func requestAccessIfNeeded(for permission: AppPermission) -> PermissionGrantStatus
    func requestAccessAndOpenSystemSettings(for permission: AppPermission)
    func requestMicrophoneAccessSynchronouslyIfNeeded(timeout: TimeInterval) -> Bool
    func primaryAction(for permission: AppPermission) -> PermissionPrimaryAction
    func isRequestInFlight(for permission: AppPermission) -> Bool
}

extension PermissionService {
    func requestAccessIfNeeded(for permission: AppPermission) -> PermissionGrantStatus {
        currentStatus(for: permission)
    }

    func requestAccessAndOpenSystemSettings(for permission: AppPermission) {
        _ = requestAccessIfNeeded(for: permission)
        openSystemSettings(for: permission)
    }

    func requestMicrophoneAccessSynchronouslyIfNeeded(timeout: TimeInterval) -> Bool {
        currentStatus(for: .microphone) == .granted
    }

    func primaryAction(for permission: AppPermission) -> PermissionPrimaryAction {
        .openSettings
    }

    func isRequestInFlight(for permission: AppPermission) -> Bool {
        false
    }
}

final class MacPermissionService: PermissionService {
    private enum SettingsOpenTiming {
        static let screenRecordingDelay: TimeInterval = 1.0
        static let microphoneDelay: TimeInterval = 1.4
        static let accessibilityDelay: TimeInterval = 0.7
        static let inputMonitoringDelay: TimeInterval = 1.5
        static let retryDelay: TimeInterval = 1.3
        static let retryCount = 2
    }

    private enum ProbeTiming {
        static let screenRecordingGrantedCacheTTL: TimeInterval = 180.0
        static let screenRecordingRecheckDelays: [TimeInterval] = [1.2, 3.5, 8.0]
        static let inputMonitoringGrantedCacheTTL: TimeInterval = 180.0
    }

    private let stateLock = NSLock()
    private var requestedInSession: Set<AppPermission> = []
    private var microphoneRequestInFlight = false

    private var screenRecordingProbeCycleID: UInt64 = 0
    private var screenRecordingProbeGrantedAt: Date?

    private var inputMonitoringProbeGrantedAt: Date?
    private var inputMonitoringPersistentTap: CFMachPort?
    private var inputMonitoringPersistentSource: CFRunLoopSource?
    private var inputMonitoringGlobalMonitor: Any?

    static func currentMicrophoneAuthorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static func requestMicrophoneAccessIfNeededAsync(completion: @escaping (AVAuthorizationStatus) -> Void) {
        let status = currentMicrophoneAuthorizationStatus()
        guard status == .notDetermined else {
            completion(status)
            return
        }

        requestMicrophoneAccessAsync(completion: completion)
    }

    static func requestMicrophoneAccessAsync(completion: @escaping (AVAuthorizationStatus) -> Void) {
        let requestAuthorization = {
            NSApp.activate(ignoringOtherApps: true)
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async {
                    completion(currentMicrophoneAuthorizationStatus())
                }
            }
        }

        if Thread.isMainThread {
            requestAuthorization()
        } else {
            DispatchQueue.main.async(execute: requestAuthorization)
        }
    }

    static func requestMicrophoneAccessSynchronously(timeout: TimeInterval) -> AVAuthorizationStatus {
        let status = currentMicrophoneAuthorizationStatus()
        guard status == .notDetermined else {
            return status
        }

        var resolvedStatus = status
        let semaphore = DispatchSemaphore(value: 0)
        requestMicrophoneAccessAsync { newStatus in
            resolvedStatus = newStatus
            semaphore.signal()
        }

        if Thread.isMainThread {
            let deadline = Date().addingTimeInterval(timeout)
            while semaphore.wait(timeout: .now()) != .success {
                guard Date() < deadline else {
                    break
                }
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
        } else {
            _ = semaphore.wait(timeout: .now() + timeout)
        }

        return resolvedStatus == .notDetermined ? currentMicrophoneAuthorizationStatus() : resolvedStatus
    }

    private func handleResolvedMicrophoneAuthorization(_ resolvedStatus: AVAuthorizationStatus) {
        setMicrophoneRequestInFlight(false)
        clearRequestedInSession(.microphone)
        if resolvedStatus == .authorized {
            probeMicrophoneCaptureStackAsync()
        }
    }

    static func shouldOpenMicrophoneSettings(for authorizationStatus: AVAuthorizationStatus) -> Bool {
        switch authorizationStatus {
        case .denied, .restricted, .authorized:
            return true
        case .notDetermined:
            return false
        @unknown default:
            return true
        }
    }

    static func microphonePrimaryAction(for authorizationStatus: AVAuthorizationStatus) -> PermissionPrimaryAction {
        switch authorizationStatus {
        case .notDetermined:
            return .requestAccess
        case .authorized, .denied, .restricted:
            return .openSettings
        @unknown default:
            return .openSettings
        }
    }

    func openSystemSettings(for permission: AppPermission) {
        for candidate in settingsURLStrings(for: permission) {
            guard let url = URL(string: candidate) else {
                continue
            }

            if NSWorkspace.shared.open(url) {
                return
            }
        }

        _ = NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    func currentStatus(for permission: AppPermission) -> PermissionGrantStatus {
        switch permission {
        case .screenRecording:
            if CGPreflightScreenCaptureAccess() {
                recordScreenRecordingProbeResult(granted: true)
                invalidateScreenRecordingProbeCycle()
                clearRequestedInSession(.screenRecording)
                return .granted
            }
            if hasRecentScreenRecordingProbeGrant() {
                return .granted
            }
            return .notGranted
        case .microphone:
            return microphoneStatus()
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .notGranted
        case .inputMonitoring:
            if CGPreflightListenEventAccess() {
                recordInputMonitoringProbeResult(granted: true)
                stopInputMonitoringPersistentRegistration()
                clearRequestedInSession(.inputMonitoring)
                return .granted
            }
            if hasRecentInputMonitoringProbeGrant() {
                return .granted
            }
            return .notGranted
        }
    }

    func primaryAction(for permission: AppPermission) -> PermissionPrimaryAction {
        switch permission {
        case .microphone:
            return Self.microphonePrimaryAction(for: Self.currentMicrophoneAuthorizationStatus())
        case .screenRecording, .accessibility, .inputMonitoring:
            return .openSettings
        }
    }

    func requestAccessIfNeeded(for permission: AppPermission) -> PermissionGrantStatus {
        switch permission {
        case .screenRecording:
            if CGPreflightScreenCaptureAccess() {
                invalidateScreenRecordingProbeCycle()
                clearRequestedInSession(.screenRecording)
                return .granted
            }
            // Avoid repeated native dialog loops; route through System Settings and
            // rely on bounded background probes to detect post-toggle grant state.
            markRequestedInSession(.screenRecording)
            scheduleScreenRecordingRecheckProbes()
            return CGPreflightScreenCaptureAccess() ? .granted : .notGranted
        case .microphone:
            let status = Self.currentMicrophoneAuthorizationStatus()
            if status == .authorized {
                probeMicrophoneCaptureStackAsync()
                setMicrophoneRequestInFlight(false)
                clearRequestedInSession(.microphone)
                return .granted
            }
            if status == .notDetermined {
                guard !isRequestInFlight(for: .microphone) else {
                    return .notGranted
                }
                markRequestedInSession(.microphone)
                setMicrophoneRequestInFlight(true)
                // Trigger the system prompt; the onboarding poller will update the status pill once the user responds.
                Self.requestMicrophoneAccessIfNeededAsync { resolvedStatus in
                    self.handleResolvedMicrophoneAuthorization(resolvedStatus)
                }
            } else {
                setMicrophoneRequestInFlight(false)
                clearRequestedInSession(.microphone)
            }
            return microphoneStatus()
        case .accessibility:
            if AXIsProcessTrusted() {
                clearRequestedInSession(.accessibility)
                return .granted
            }
            markRequestedInSession(.accessibility)
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let options = [promptKey: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return AXIsProcessTrusted() ? .granted : .notGranted
        case .inputMonitoring:
            if CGPreflightListenEventAccess() {
                recordInputMonitoringProbeResult(granted: true)
                stopInputMonitoringPersistentRegistration()
                clearRequestedInSession(.inputMonitoring)
                return .granted
            }
            markRequestedInSession(.inputMonitoring)
            startInputMonitoringPersistentRegistration()
            _ = CGRequestListenEventAccess()
            return CGPreflightListenEventAccess() ? .granted : .notGranted
        }
    }

    func requestAccessAndOpenSystemSettings(for permission: AppPermission) {
        switch permission {
        case .microphone:
            let microphoneAuthorizationStatus = Self.currentMicrophoneAuthorizationStatus()
            if microphoneAuthorizationStatus == .authorized {
                probeMicrophoneCaptureStackAsync()
                setMicrophoneRequestInFlight(false)
                clearRequestedInSession(.microphone)
                openSystemSettings(for: permission)
                return
            }
            if microphoneAuthorizationStatus == .notDetermined {
                guard !isRequestInFlight(for: .microphone) else {
                    return
                }
                markRequestedInSession(.microphone)
                setMicrophoneRequestInFlight(true)
                Self.requestMicrophoneAccessIfNeededAsync { resolvedStatus in
                    self.handleResolvedMicrophoneAuthorization(resolvedStatus)
                }
                return
            }

            setMicrophoneRequestInFlight(false)
            clearRequestedInSession(.microphone)
            if Self.shouldOpenMicrophoneSettings(for: microphoneAuthorizationStatus) {
                openSystemSettings(for: permission)
            }
        case .inputMonitoring:
            if currentStatus(for: permission) == .granted {
                recordInputMonitoringProbeResult(granted: true)
                clearRequestedInSession(.inputMonitoring)
                openSystemSettings(for: permission)
                return
            }
            if !hasRequestedInSession(.inputMonitoring) {
                _ = requestAccessIfNeeded(for: permission)
            } else {
                startInputMonitoringPersistentRegistration()
            }
            if currentStatus(for: permission) == .granted {
                clearRequestedInSession(.inputMonitoring)
                openSystemSettings(for: permission)
                return
            }
            openSystemSettingsAfterRegistration(
                for: permission,
                initialDelay: SettingsOpenTiming.inputMonitoringDelay
            )
        case .screenRecording:
            if currentStatus(for: permission) == .granted {
                invalidateScreenRecordingProbeCycle()
                clearRequestedInSession(.screenRecording)
                openSystemSettings(for: permission)
                return
            }
            _ = requestAccessIfNeeded(for: permission)
            if currentStatus(for: permission) == .granted {
                invalidateScreenRecordingProbeCycle()
                clearRequestedInSession(.screenRecording)
                openSystemSettings(for: permission)
                return
            }
            openSystemSettingsAfterRegistration(
                for: permission,
                initialDelay: SettingsOpenTiming.screenRecordingDelay
            )
        case .accessibility:
            if currentStatus(for: permission) == .granted {
                clearRequestedInSession(.accessibility)
                openSystemSettings(for: permission)
                return
            }
            if !hasRequestedInSession(.accessibility) {
                _ = requestAccessIfNeeded(for: permission)
            }
            if currentStatus(for: permission) == .granted {
                clearRequestedInSession(.accessibility)
                openSystemSettings(for: permission)
                return
            }
            openSystemSettingsAfterRegistration(
                for: permission,
                initialDelay: SettingsOpenTiming.accessibilityDelay
            )
        }
    }

    private func settingsURLStrings(for permission: AppPermission) -> [String] {
        switch permission {
        case .screenRecording:
            return [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenRecording",
                "x-apple.systempreferences:com.apple.preference.security?Privacy"
            ]
        case .microphone:
            return [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
                "x-apple.systempreferences:com.apple.preference.security?Privacy"
            ]
        case .accessibility:
            return [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
                "x-apple.systempreferences:com.apple.preference.security?Privacy"
            ]
        case .inputMonitoring:
            return [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
                "x-apple.systempreferences:com.apple.preference.security?Privacy"
            ]
        }
    }

    private func microphoneStatus() -> PermissionGrantStatus {
        switch Self.currentMicrophoneAuthorizationStatus() {
        case .authorized:
            return .granted
        case .notDetermined, .denied, .restricted:
            return .notGranted
        @unknown default:
            return .unknown
        }
    }

    func requestMicrophoneAccessSynchronouslyIfNeeded(timeout: TimeInterval) -> Bool {
        let status = Self.requestMicrophoneAccessSynchronously(timeout: timeout)
        if status == .authorized {
            probeMicrophoneCaptureStackAsync()
            setMicrophoneRequestInFlight(false)
            clearRequestedInSession(.microphone)
            return true
        }
        return false
    }

    func isRequestInFlight(for permission: AppPermission) -> Bool {
        guard permission == .microphone else {
            return false
        }
        stateLock.lock()
        let inFlight = microphoneRequestInFlight
        stateLock.unlock()
        return inFlight
    }

    private func installInputMonitoringEventTap(duration: TimeInterval?) -> Bool {
        let installProbe = { () -> Bool in
            let mask = (1 as CGEventMask) << CGEventType.keyDown.rawValue
            let callback: CGEventTapCallBack = { _, _, event, _ in
                Unmanaged.passUnretained(event)
            }
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: nil
            ) else {
                return false
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)

            if let duration {
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    CGEvent.tapEnable(tap: tap, enable: false)
                    CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
                    CFMachPortInvalidate(tap)
                }
            } else {
                self.inputMonitoringPersistentTap = tap
                self.inputMonitoringPersistentSource = source
            }
            return true
        }

        if Thread.isMainThread {
            return installProbe()
        }

        var success = false
        DispatchQueue.main.sync {
            success = installProbe()
        }
        return success
    }

    private func openSystemSettingsAfterRegistration(for permission: AppPermission, initialDelay: TimeInterval) {
        openSystemSettingsAttempt(for: permission, attempt: 0, after: initialDelay)
    }

    private func openSystemSettingsAttempt(for permission: AppPermission, attempt: Int, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else {
                return
            }
            self.openSystemSettings(for: permission)

            guard attempt < SettingsOpenTiming.retryCount else {
                return
            }
            guard self.currentStatus(for: permission) != .granted else {
                return
            }
            self.openSystemSettingsAttempt(
                for: permission,
                attempt: attempt + 1,
                after: SettingsOpenTiming.retryDelay
            )
        }
    }

    private func markRequestedInSession(_ permission: AppPermission) {
        stateLock.lock()
        requestedInSession.insert(permission)
        stateLock.unlock()
    }

    private func clearRequestedInSession(_ permission: AppPermission) {
        stateLock.lock()
        requestedInSession.remove(permission)
        stateLock.unlock()
    }

    private func setMicrophoneRequestInFlight(_ inFlight: Bool) {
        stateLock.lock()
        microphoneRequestInFlight = inFlight
        stateLock.unlock()
    }

    private func hasRequestedInSession(_ permission: AppPermission) -> Bool {
        stateLock.lock()
        let requested = requestedInSession.contains(permission)
        stateLock.unlock()
        return requested
    }

    private func hasRecentScreenRecordingProbeGrant() -> Bool {
        stateLock.lock()
        let grantedAt = screenRecordingProbeGrantedAt
        stateLock.unlock()
        guard let grantedAt else {
            return false
        }
        return Date().timeIntervalSince(grantedAt) <= ProbeTiming.screenRecordingGrantedCacheTTL
    }

    private func hasRecentInputMonitoringProbeGrant() -> Bool {
        stateLock.lock()
        let grantedAt = inputMonitoringProbeGrantedAt
        stateLock.unlock()
        guard let grantedAt else {
            return false
        }
        return Date().timeIntervalSince(grantedAt) <= ProbeTiming.inputMonitoringGrantedCacheTTL
    }

    private func recordScreenRecordingProbeResult(granted: Bool) {
        stateLock.lock()
        if granted {
            screenRecordingProbeGrantedAt = Date()
        } else {
            screenRecordingProbeGrantedAt = nil
        }
        stateLock.unlock()
    }

    private func recordInputMonitoringProbeResult(granted: Bool) {
        stateLock.lock()
        if granted {
            inputMonitoringProbeGrantedAt = Date()
        } else {
            inputMonitoringProbeGrantedAt = nil
        }
        stateLock.unlock()
    }

    private func invalidateScreenRecordingProbeCycle() {
        stateLock.lock()
        screenRecordingProbeCycleID &+= 1
        stateLock.unlock()
    }

    private func currentScreenRecordingProbeCycleID() -> UInt64 {
        stateLock.lock()
        let cycleID = screenRecordingProbeCycleID
        stateLock.unlock()
        return cycleID
    }

    private func scheduleScreenRecordingRecheckProbes() {
        invalidateScreenRecordingProbeCycle()
        let cycleID = currentScreenRecordingProbeCycleID()
        for delay in ProbeTiming.screenRecordingRecheckDelays {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else {
                    return
                }
                self.probeScreenRecordingCaptureAsync(expectedCycleID: cycleID)
            }
        }
    }

    private func finishScreenRecordingProbe(granted: Bool, expectedCycleID: UInt64?) {
        if let expectedCycleID, expectedCycleID != currentScreenRecordingProbeCycleID() {
            return
        }
        if granted {
            recordScreenRecordingProbeResult(granted: true)
            clearRequestedInSession(.screenRecording)
            invalidateScreenRecordingProbeCycle()
        }
    }

    private func startInputMonitoringPersistentRegistration() {
        let install = {
            self.stopInputMonitoringPersistentRegistration()
            let eventTapProbeInstalled = self.installInputMonitoringEventTap(duration: nil)
            self.recordInputMonitoringProbeResult(granted: eventTapProbeInstalled)

            self.inputMonitoringGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { _ in }
        }

        if Thread.isMainThread {
            install()
        } else {
            DispatchQueue.main.async(execute: install)
        }
    }

    private func stopInputMonitoringPersistentRegistration() {
        let stop = {
            if let monitor = self.inputMonitoringGlobalMonitor {
                NSEvent.removeMonitor(monitor)
            }
            self.inputMonitoringGlobalMonitor = nil

            if let source = self.inputMonitoringPersistentSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            self.inputMonitoringPersistentSource = nil

            if let tap = self.inputMonitoringPersistentTap {
                CGEvent.tapEnable(tap: tap, enable: false)
                CFMachPortInvalidate(tap)
            }
            self.inputMonitoringPersistentTap = nil
        }

        if Thread.isMainThread {
            stop()
        } else {
            DispatchQueue.main.async(execute: stop)
        }
    }

    private func probeScreenRecordingCaptureAsync() {
        probeScreenRecordingCaptureAsync(expectedCycleID: nil)
    }

    private func probeScreenRecordingCaptureAsync(expectedCycleID: UInt64?) {
        DispatchQueue.global(qos: .utility).async {
            if let expectedCycleID, expectedCycleID != self.currentScreenRecordingProbeCycleID() {
                return
            }
            let granted = (try? DesktopScreenshotService.captureMainDisplayPNGScreenCaptureKitOnly(excludingWindowNumbers: [])) != nil
            self.finishScreenRecordingProbe(granted: granted, expectedCycleID: expectedCycleID)
        }
    }

    private func probeMicrophoneCaptureStackAsync() {
        DispatchQueue.global(qos: .utility).async {
            guard Self.currentMicrophoneAuthorizationStatus() == .authorized else {
                return
            }
            guard
                let device = AVCaptureDevice.default(for: .audio),
                let input = try? AVCaptureDeviceInput(device: device)
            else {
                return
            }

            let session = AVCaptureSession()
            session.beginConfiguration()
            if session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
            session.startRunning()
            Thread.sleep(forTimeInterval: 0.35)
            session.stopRunning()
        }
    }

}
