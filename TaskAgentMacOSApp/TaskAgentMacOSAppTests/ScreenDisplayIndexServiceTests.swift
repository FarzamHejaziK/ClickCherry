import CoreGraphics
import Testing
@testable import TaskAgentMacOSApp

struct ScreenDisplayIndexServiceTests {
    @Test
    func orderedDisplayIDsForScreencaptureMovesPrimaryDisplayToFront() {
        let mainDisplayID = CGDirectDisplayID(200)
        let appKitOrder: [CGDirectDisplayID] = [100, 200, 300]

        let ordered = ScreenDisplayIndexService.orderedDisplayIDsForScreencapture(
            mainDisplayID: mainDisplayID,
            appKitOrder: appKitOrder
        )

        #expect(ordered == [200, 100, 300])
    }

    @Test
    func orderedDisplayIDsForScreencaptureLeavesOrderWhenPrimaryAlreadyFirst() {
        let mainDisplayID = CGDirectDisplayID(100)
        let appKitOrder: [CGDirectDisplayID] = [100, 200, 300]

        let ordered = ScreenDisplayIndexService.orderedDisplayIDsForScreencapture(
            mainDisplayID: mainDisplayID,
            appKitOrder: appKitOrder
        )

        #expect(ordered == appKitOrder)
    }

    @Test
    func orderedDisplayIDsForScreencaptureLeavesOrderWhenPrimaryMissing() {
        let mainDisplayID = CGDirectDisplayID(999)
        let appKitOrder: [CGDirectDisplayID] = [100, 200, 300]

        let ordered = ScreenDisplayIndexService.orderedDisplayIDsForScreencapture(
            mainDisplayID: mainDisplayID,
            appKitOrder: appKitOrder
        )

        #expect(ordered == appKitOrder)
    }
}
