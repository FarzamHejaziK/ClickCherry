import Foundation

extension MainShellStateStore {
    func refreshBrowserAutomationState() {
        browserAutomationSetupState = BrowserAutomationSetupState(
            hasPlaywrightMCPBridgeToken: browserBridgeTokenStore.hasPlaywrightMCPBridgeToken()
        )
    }

    @discardableResult
    func savePlaywrightMCPBridgeToken(_ rawToken: String) -> Bool {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            browserAutomationStatusMessage = nil
            browserAutomationErrorMessage = "Playwright MCP Bridge token cannot be empty."
            return false
        }

        do {
            try browserBridgeTokenStore.setPlaywrightMCPBridgeToken(token)
            Self.applyPlaywrightMCPBridgeTokenEnvironment(token: token)
            refreshBrowserAutomationState()
            browserAutomationStatusMessage = "Saved Playwright MCP Bridge token."
            browserAutomationErrorMessage = nil
            return true
        } catch {
            browserAutomationStatusMessage = nil
            browserAutomationErrorMessage = "Failed to save Playwright MCP Bridge token."
            return false
        }
    }

    func clearPlaywrightMCPBridgeToken() {
        do {
            try browserBridgeTokenStore.setPlaywrightMCPBridgeToken(nil)
            Self.applyPlaywrightMCPBridgeTokenEnvironment(token: nil)
            refreshBrowserAutomationState()
            browserAutomationStatusMessage = "Removed Playwright MCP Bridge token."
            browserAutomationErrorMessage = nil
        } catch {
            browserAutomationStatusMessage = nil
            browserAutomationErrorMessage = "Failed to remove Playwright MCP Bridge token."
        }
    }
}
