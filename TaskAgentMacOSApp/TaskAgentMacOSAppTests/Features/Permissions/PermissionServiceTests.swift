import AVFoundation
import Testing
@testable import TaskAgentMacOSApp

struct PermissionServiceTests {
    @Test
    func microphonePrimaryActionRequestsAccessWhenStatusIsNotDetermined() {
        #expect(
            MacPermissionService.microphonePrimaryAction(for: .notDetermined) == .requestAccess
        )
    }

    @Test
    func microphonePrimaryActionUsesSettingsAfterAuthorizationDecision() {
        #expect(MacPermissionService.microphonePrimaryAction(for: .authorized) == .openSettings)
        #expect(MacPermissionService.microphonePrimaryAction(for: .denied) == .openSettings)
        #expect(MacPermissionService.microphonePrimaryAction(for: .restricted) == .openSettings)
    }
}
