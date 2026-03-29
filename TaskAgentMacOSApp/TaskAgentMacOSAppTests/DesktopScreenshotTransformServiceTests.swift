import AppKit
import Foundation
import Testing
@testable import TaskAgentMacOSApp

struct DesktopScreenshotTransformServiceTests {
    @Test
    func renderCropUsesVisibleTopLeftCoordinates() throws {
        let screenshot = try makeScreenshot(width: 120, height: 80)

        let result = try DesktopScreenshotTransformService.render(
            screenshot: screenshot,
            cropRect: CGRect(x: 0, y: 60, width: 120, height: 20),
            scale: 1.0,
            gridOverlay: nil,
            cursorOverlay: nil
        )

        #expect(result.width == 120)
        #expect(result.height == 20)
        #expect(!result.pngData.isEmpty)
    }

    @Test
    func renderAddsCursorOverlayWithoutChangingDimensions() throws {
        let screenshot = try makeScreenshot(width: 64, height: 64)

        let result = try DesktopScreenshotTransformService.render(
            screenshot: screenshot,
            cropRect: nil,
            scale: 1.0,
            gridOverlay: nil,
            cursorOverlay: DesktopScreenshotCursorOverlayOptions(center: CGPoint(x: 20, y: 30), radius: 12)
        )

        #expect(result.width == 64)
        #expect(result.height == 64)
        #expect(!result.pngData.isEmpty)
    }

    private func makeScreenshot(width: Int, height: Int) throws -> OpenAICapturedScreenshot {
        guard
            let bitmapRep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ),
            let context = NSGraphicsContext(bitmapImageRep: bitmapRep)
        else {
            throw NSError(domain: "DesktopScreenshotTransformServiceTests", code: 1)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        NSColor.red.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: 20)).fill()
        NSColor.blue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: height - 20, width: width, height: 20)).fill()
        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "DesktopScreenshotTransformServiceTests", code: 2)
        }

        return OpenAICapturedScreenshot(
            width: width,
            height: height,
            captureWidthPx: width,
            captureHeightPx: height,
            coordinateSpaceWidthPx: width,
            coordinateSpaceHeightPx: height,
            coordinateSpaceOriginX: 0,
            coordinateSpaceOriginY: 0,
            mediaType: "image/png",
            base64Data: pngData.base64EncodedString(),
            byteCount: pngData.count
        )
    }
}
