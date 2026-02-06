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
}

final class MacPermissionService: PermissionService {
    func openSystemSettings(for permission: AppPermission) {
        guard let url = URL(string: settingsURLString(for: permission)) else {
            return
        }

        NSWorkspace.shared.open(url)
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

    private func settingsURLString(for permission: AppPermission) -> String {
        switch permission {
        case .screenRecording:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .accessibility:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .automation:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        }
    }
}
