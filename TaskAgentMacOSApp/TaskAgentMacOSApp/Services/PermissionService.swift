import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum AppPermission: Equatable {
    case screenRecording
    case accessibility
    case automation
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
}

extension PermissionService {
    func requestAccessIfNeeded(for permission: AppPermission) -> PermissionGrantStatus {
        currentStatus(for: permission)
    }
}

final class MacPermissionService: PermissionService {
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
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .notGranted
        case .automation:
            // Generic automation status cannot be reliably preflighted without a target app.
            return .unknown
        }
    }

    func requestAccessIfNeeded(for permission: AppPermission) -> PermissionGrantStatus {
        switch permission {
        case .screenRecording:
            if CGPreflightScreenCaptureAccess() {
                return .granted
            }
            _ = CGRequestScreenCaptureAccess()
            return CGPreflightScreenCaptureAccess() ? .granted : .notGranted
        case .accessibility:
            if AXIsProcessTrusted() {
                return .granted
            }
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let options = [promptKey: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return AXIsProcessTrusted() ? .granted : .notGranted
        case .automation:
            // Generic automation status cannot be reliably preflighted without a target app.
            return .unknown
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
        case .accessibility:
            return [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
                "x-apple.systempreferences:com.apple.preference.security?Privacy"
            ]
        case .automation:
            return [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
                "x-apple.systempreferences:com.apple.preference.security?Privacy"
            ]
        }
    }
}
