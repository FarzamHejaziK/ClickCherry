import Foundation
import AppKit

extension MainShellStateStore {
    // MARK: - Provider Setup

    func permissionStatus(for permission: AppPermission) -> PermissionGrantStatus {
        permissionService.currentStatus(for: permission)
    }

    func openPermissionSettings(for permission: AppPermission) {
        permissionService.requestAccessAndOpenSystemSettings(for: permission)
    }

    func permissionPrimaryAction(for permission: AppPermission) -> PermissionPrimaryAction {
        permissionService.primaryAction(for: permission)
    }

    func isPermissionRequestInFlight(for permission: AppPermission) -> Bool {
        permissionService.isRequestInFlight(for: permission)
    }

    func permissionActionLabel(for permission: AppPermission) -> String {
        permissionPrimaryAction(for: permission).buttonTitle
    }

    func resetOnboardingAndReturnToSetup() {
        userDefaults.set(false, forKey: "onboarding.completed")
        userDefaults.synchronize()
        NotificationCenter.default.post(name: .clickCherryResetOnboardingRequested, object: nil)
    }

    func resetSetupAndReturnToOnboarding() {
        do {
            try apiKeyStore.setKey(nil, for: .openAI)
            try apiKeyStore.setKey(nil, for: .gemini)
            updateProviderSetupState(saved: false, for: .openAI)
            updateProviderSetupState(saved: false, for: .gemini)
            apiKeyStatusMessage = "Cleared OpenAI/Gemini API keys and returned to onboarding."
            apiKeyErrorMessage = "OpenAI API key is not saved."
        } catch {
            apiKeyStatusMessage = nil
            apiKeyErrorMessage = "Failed to clear one or more API keys. Onboarding reset still applied."
        }

        let permissionResetOutcome = Self.resetSystemPermissionsViaTCC()
        switch permissionResetOutcome {
        case .success:
            errorMessage = "Reset macOS permissions and onboarding for this app. The app will relaunch so macOS permission state fully refreshes."
        case .notAvailable:
            errorMessage = "Could not reset macOS permissions automatically. Use System Settings > Privacy & Security to revoke them manually."
        case .failed:
            errorMessage = "Automatic permission reset failed. Use System Settings > Privacy & Security to revoke permissions manually."
        }
        resetOnboardingAndReturnToSetup()

        if permissionResetOutcome == .success {
            Self.relaunchApplicationAfterReset()
        }
    }

    func refreshProviderKeysState() {
        providerSetupState = ProviderSetupState(
            hasOpenAIKey: apiKeyStore.hasKey(for: .openAI),
            hasGeminiKey: apiKeyStore.hasKey(for: .gemini)
        )
        if providerSetupState.hasOpenAIKey {
            if apiKeyErrorMessage == "OpenAI API key is not saved." {
                apiKeyErrorMessage = nil
            }
        } else {
            apiKeyErrorMessage = "OpenAI API key is not saved."
        }
    }

    @discardableResult
    func saveProviderKey(_ rawKey: String, for provider: ProviderIdentifier) -> Bool {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            apiKeyStatusMessage = nil
            apiKeyErrorMessage = "API key cannot be empty."
            return false
        }

        do {
            try apiKeyStore.setKey(key, for: provider)
            updateProviderSetupState(saved: true, for: provider)
            apiKeyStatusMessage = "Saved \(providerDisplayName(provider)) API key."
            if provider == .openAI {
                apiKeyErrorMessage = nil
            }
            return true
        } catch {
            apiKeyStatusMessage = nil
            apiKeyErrorMessage = "Failed to save \(providerDisplayName(provider)) API key."
            return false
        }
    }

    func clearProviderKey(for provider: ProviderIdentifier) {
        do {
            try apiKeyStore.setKey(nil, for: provider)
            updateProviderSetupState(saved: false, for: provider)
            apiKeyStatusMessage = "Removed \(providerDisplayName(provider)) API key."
            apiKeyErrorMessage = provider == .openAI ? "OpenAI API key is not saved." : nil
        } catch {
            apiKeyStatusMessage = nil
            apiKeyErrorMessage = "Failed to remove \(providerDisplayName(provider)) API key."
        }
    }

    private enum PermissionResetOutcome {
        case success
        case notAvailable
        case failed
    }

    private static func resetSystemPermissionsViaTCC() -> PermissionResetOutcome {
        // Prevent test execution from mutating host TCC state.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return .notAvailable
        }

        guard let bundleIdentifier = Bundle.main.bundleIdentifier, !bundleIdentifier.isEmpty else {
            return .notAvailable
        }

        let executable = "/usr/bin/tccutil"
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return .notAvailable
        }

        if runTCCReset(executablePath: executable, service: "All", bundleIdentifier: bundleIdentifier) {
            return .success
        }

        let services = ["Accessibility", "Microphone", "ScreenCapture", "ListenEvent", "AppleEvents", "PostEvent"]
        var didResetAtLeastOne = false
        for service in services {
            if runTCCReset(executablePath: executable, service: service, bundleIdentifier: bundleIdentifier) {
                didResetAtLeastOne = true
            }
        }
        return didResetAtLeastOne ? .success : .failed
    }

    private static func runTCCReset(executablePath: String, service: String, bundleIdentifier: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["reset", service, bundleIdentifier]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func relaunchApplicationAfterReset() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        let appBundlePath = Bundle.main.bundlePath
        guard !appBundlePath.isEmpty else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            relaunch.arguments = ["-n", appBundlePath]
            try? relaunch.run()
            NSApp.terminate(nil)
        }
    }

    private func updateProviderSetupState(saved: Bool, for provider: ProviderIdentifier) {
        switch provider {
        case .openAI:
            providerSetupState.hasOpenAIKey = saved
        case .gemini:
            providerSetupState.hasGeminiKey = saved
        }
    }

    private func providerDisplayName(_ provider: ProviderIdentifier) -> String {
        switch provider {
        case .openAI:
            return "OpenAI"
        case .gemini:
            return "Gemini"
        }
    }
}
