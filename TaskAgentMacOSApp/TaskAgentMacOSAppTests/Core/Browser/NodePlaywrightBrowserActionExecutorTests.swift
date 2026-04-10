import Foundation
import Testing
@testable import TaskAgentMacOSApp

struct NodePlaywrightBrowserActionExecutorTests {
    @Test
    func nodeExecutableSearchPathsIncludeCommonAbsoluteFallbacks() {
        let candidates = NodePlaywrightBrowserActionExecutor.nodeExecutableSearchPaths(
            nodeExecutableName: "node",
            environment: ["PATH": "/usr/bin:/bin"],
            additionalSearchPaths: [],
            commonSearchPaths: nil
        )

        #expect(candidates.contains("/usr/bin/node"))
        #expect(candidates.contains("/opt/homebrew/bin/node"))
        #expect(candidates.contains("/usr/local/bin/node"))
    }

    @Test
    func attachOrLaunchChromeUsesExplicitNodeSearchPathWhenPATHIsThin() async throws {
        let fixture = try makeBrowserSidecarFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let executor = NodePlaywrightBrowserActionExecutor(
            sidecarDirectoryURL: fixture.sidecarDirectoryURL,
            nodeExecutableName: "node",
            nodeSearchPaths: [fixture.fakeNodeExecutableURL.path],
            environment: ["PATH": "/usr/bin:/bin"],
        )

        let session = try await executor.attachOrLaunchChrome(
            options: BrowserLaunchOptions(profileMode: .managed, profileHint: nil, profileName: "qa-profile", profileDirectory: nil, userDataDir: nil, forceRelaunch: nil)
        )

        #expect(session.debuggingPort == 9222)
        #expect(session.launched == true)
        #expect(session.currentPage?.url == "https://example.com")
        #expect(session.profile?.displayName == "qa-profile")
    }

    @Test
    func attachOrLaunchChromeReportsSearchedNodeLocationsWhenUnavailable() async throws {
        let fixture = try makeBrowserSidecarFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let executor = NodePlaywrightBrowserActionExecutor(
            sidecarDirectoryURL: fixture.sidecarDirectoryURL,
            nodeExecutableName: "node",
            nodeSearchPaths: [],
            commonNodeSearchPaths: ["/tmp/missing-node-a", "/tmp/missing-node-b"],
            environment: ["PATH": "/usr/bin:/bin"]
        )

        do {
            _ = try await executor.attachOrLaunchChrome(options: nil)
            #expect(Bool(false))
        } catch let error as BrowserActionExecutorError {
            guard case .nodeUnavailable(let message) = error else {
                #expect(Bool(false))
                return
            }
            #expect(message.contains("/tmp/missing-node-a"))
            #expect(message.contains("/tmp/missing-node-b"))
        }
    }

    private func makeBrowserSidecarFixture() throws -> (rootURL: URL, sidecarDirectoryURL: URL, fakeNodeExecutableURL: URL) {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sidecarDirectoryURL = rootURL.appendingPathComponent("browser_sidecar", isDirectory: true)
        let playwrightDirectoryURL = sidecarDirectoryURL
            .appendingPathComponent("node_modules", isDirectory: true)
            .appendingPathComponent("playwright", isDirectory: true)

        try fileManager.createDirectory(at: playwrightDirectoryURL, withIntermediateDirectories: true)

        try "// fake sidecar for node resolution tests\n".write(
            to: sidecarDirectoryURL.appendingPathComponent("browser_action.mjs", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "{}".write(
            to: playwrightDirectoryURL.appendingPathComponent("package.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let fakeNodeExecutableURL = rootURL.appendingPathComponent("fake-node", isDirectory: false)
        try """
        #!/bin/sh
        cat >/dev/null
        printf '%s' '{"ok":true,"message":"Attached.","state":{"debugging_port":9222},"data":{"debugging_port":9222,"launched":true,"tab_count":1,"current_page":{"title":"Example","url":"https://example.com","target_id":"tab-1"},"profile":{"kind":"managed","display_name":"qa-profile","user_data_dir":"/tmp/qa-profile","is_default":false}}}'
        """.write(
            to: fakeNodeExecutableURL,
            atomically: true,
            encoding: .utf8
        )
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeNodeExecutableURL.path)

        return (rootURL, sidecarDirectoryURL, fakeNodeExecutableURL)
    }
}
