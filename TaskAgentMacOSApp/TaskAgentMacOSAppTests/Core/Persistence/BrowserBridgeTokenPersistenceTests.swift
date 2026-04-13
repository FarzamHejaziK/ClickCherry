import Testing
@testable import TaskAgentMacOSApp

struct BrowserBridgeTokenPersistenceTests {
    @Test
    func keychainBrowserBridgeTokenStoreUsesInMemoryPathDuringXCTest() throws {
        let tokenStore = KeychainBrowserBridgeTokenStore()

        try tokenStore.setPlaywrightMCPBridgeToken("bridge-token")
        #expect(tokenStore.hasPlaywrightMCPBridgeToken())
        #expect(try tokenStore.readPlaywrightMCPBridgeToken() == "bridge-token")

        try tokenStore.setPlaywrightMCPBridgeToken(nil)
        #expect(!tokenStore.hasPlaywrightMCPBridgeToken())
        #expect(try tokenStore.readPlaywrightMCPBridgeToken() == nil)
    }
}
