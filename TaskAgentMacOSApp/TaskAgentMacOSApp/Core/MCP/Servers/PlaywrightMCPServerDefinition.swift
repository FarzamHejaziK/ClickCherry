import Foundation

enum PlaywrightMCPServerDefinition {
    static func extensionServer() -> MCPServerDefinition {
        return MCPServerDefinition(
            id: "playwright_mcp_extension",
            displayName: "Playwright MCP Bridge",
            command: "npx",
            args: ["@playwright/mcp@latest", "--extension"],
            startupTimeout: 20,
            enabledByDefault: true
        )
    }
}
