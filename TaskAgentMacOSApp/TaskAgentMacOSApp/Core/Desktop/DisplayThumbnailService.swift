import Foundation
import CoreGraphics

enum DisplayThumbnailService {
    static func captureThumbnailForDisplayIndex(_ displayIndex: Int) throws -> CGImage {
        let idx = max(0, displayIndex - 1)
        let screens = ScreenDisplayIndexService.orderedScreensMainFirst()
        guard idx < screens.count else {
            throw DesktopScreenshotServiceError.captureFailed
        }
        guard let displayID = ScreenDisplayIndexService.cgDisplayID(for: screens[idx]) else {
            throw DesktopScreenshotServiceError.captureFailed
        }
        return try DesktopScreenshotService.captureDisplayThumbnailCGImage(displayID: displayID, maxWidth: 520)
    }
}

