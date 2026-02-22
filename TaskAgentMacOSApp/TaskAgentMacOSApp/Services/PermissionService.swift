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

protocol PermissionService {
    func openSystemSettings(for permission: AppPermission)
    func currentStatus(for permission: AppPermission) -> PermissionGrantStatus
    func requestAccessIfNeeded(for permission: AppPermission) -> PermissionGrantStatus
    func requestAccessAndOpenSystemSettings(for permission: AppPermission)
}

extension PermissionService {
    func requestAccessIfNeeded(for permission: AppPermission) -> PermissionGrantStatus {
        currentStatus(for: permission)
    }

    func requestAccessAndOpenSystemSettings(for permission: AppPermission) {
        _ = requestAccessIfNeeded(for: permission)
        openSystemSettings(for: permission)
    }
}

final class MacPermissionService: PermissionService {
    private enum SettingsOpenTiming {
        static let screenRecordingDelay: TimeInterval = 1.0
        static let microphoneDelay: TimeInterval = 0.8
        static let accessibilityDelay: TimeInterval = 0.7
        static let inputMonitoringDelay: TimeInterval = 1.5
        static let retryDelay: TimeInterval = 1.3
        static let retryCount = 2
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
            return CGPreflightScreenCaptureAccess() ? .granted : .notGranted
        case .microphone:
            return microphoneStatus()
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .notGranted
        case .inputMonitoring:
            return CGPreflightListenEventAccess() ? .granted : .notGranted
        }
    }

    func requestAccessIfNeeded(for permission: AppPermission) -> PermissionGrantStatus {
        switch permission {
        case .screenRecording:
            if CGPreflightScreenCaptureAccess() {
                return .granted
            }
            _ = CGRequestScreenCaptureAccess()
            probeScreenRecordingCaptureAsync()
            return CGPreflightScreenCaptureAccess() ? .granted : .notGranted
        case .microphone:
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            if status == .authorized {
                probeMicrophoneCaptureStackAsync()
                return .granted
            }
            if status == .notDetermined {
                // Trigger the system prompt; the onboarding poller will update the status pill once the user responds.
                AVCaptureDevice.requestAccess(for: .audio) { _ in }
            }
            return microphoneStatus()
        case .accessibility:
            if AXIsProcessTrusted() {
                return .granted
            }
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let options = [promptKey: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return AXIsProcessTrusted() ? .granted : .notGranted
        case .inputMonitoring:
            if CGPreflightListenEventAccess() {
                return .granted
            }
            _ = CGRequestListenEventAccess()
            probeInputMonitoringRegistrationBurst()
            return CGPreflightListenEventAccess() ? .granted : .notGranted
        }
    }

    func requestAccessAndOpenSystemSettings(for permission: AppPermission) {
        switch permission {
        case .microphone:
            let microphoneAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            if microphoneAuthorizationStatus == .authorized {
                probeMicrophoneCaptureStackAsync()
                openSystemSettings(for: permission)
                return
            }
            if microphoneAuthorizationStatus == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    if granted {
                        self.probeMicrophoneCaptureStackAsync()
                    }
                }
                return
            }

            openSystemSettingsAfterRegistration(
                for: permission,
                initialDelay: SettingsOpenTiming.microphoneDelay
            )
        case .inputMonitoring:
            if currentStatus(for: permission) == .granted {
                openSystemSettings(for: permission)
                return
            }
            _ = requestAccessIfNeeded(for: permission)
            if currentStatus(for: permission) == .granted {
                openSystemSettings(for: permission)
                return
            }
            openSystemSettingsAfterRegistration(
                for: permission,
                initialDelay: SettingsOpenTiming.inputMonitoringDelay
            )
        case .screenRecording:
            if currentStatus(for: permission) == .granted {
                openSystemSettings(for: permission)
                return
            }
            _ = requestAccessIfNeeded(for: permission)
            if currentStatus(for: permission) == .granted {
                openSystemSettings(for: permission)
                return
            }
            openSystemSettingsAfterRegistration(
                for: permission,
                initialDelay: SettingsOpenTiming.screenRecordingDelay
            )
        case .accessibility:
            if currentStatus(for: permission) == .granted {
                openSystemSettings(for: permission)
                return
            }
            _ = requestAccessIfNeeded(for: permission)
            if currentStatus(for: permission) == .granted {
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
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .notDetermined, .denied, .restricted:
            return .notGranted
        @unknown default:
            return .unknown
        }
    }

    private func probeInputMonitoringEventTap(duration: TimeInterval) -> Bool {
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

            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                CGEvent.tapEnable(tap: tap, enable: false)
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
                CFMachPortInvalidate(tap)
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

    private func probeInputMonitoringRegistrationBurst() {
        _ = probeInputMonitoringEventTap(duration: 1.2)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            _ = self.probeInputMonitoringEventTap(duration: 1.2)
        }
    }

    private func probeScreenRecordingCaptureAsync() {
        DispatchQueue.global(qos: .utility).async {
            _ = try? DesktopScreenshotService.captureMainDisplayPNGScreenCaptureKitOnly(excludingWindowNumbers: [])
        }
    }

    private func probeMicrophoneCaptureStackAsync() {
        DispatchQueue.global(qos: .utility).async {
            guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
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
