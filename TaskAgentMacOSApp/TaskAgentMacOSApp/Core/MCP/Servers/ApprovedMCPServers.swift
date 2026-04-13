import Foundation

enum ApprovedMCPServers {
    static func defaultDefinitions() -> [MCPServerDefinition] {
        [
            PlaywrightMCPServerDefinition.extensionServer()
        ]
    }
}
