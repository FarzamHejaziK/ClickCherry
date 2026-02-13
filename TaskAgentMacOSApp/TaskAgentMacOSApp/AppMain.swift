import AppKit
import SwiftUI

@main
struct TaskAgentMacOSApp: App {
    init() {
        // Swift package executables may launch without foreground activation.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}
