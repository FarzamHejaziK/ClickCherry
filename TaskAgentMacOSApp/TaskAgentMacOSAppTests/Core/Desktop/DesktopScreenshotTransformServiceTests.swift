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
            cropRect: CGRect(x: 0, y: 0, width: 120, height: 20),
            scale: 1.0,
            gridOverlay: nil,
            cursorOverlay: nil
        )

        #expect(result.width == 120)
        #expect(result.height == 20)
        #expect(!result.pngData.isEmpty)
        #expect(colorAtTopLeft(in: result.pngData, x: 10, y: 10)?.isMostlyBlue == true)
    }

    @Test
    func renderAddsCursorOverlayWithoutChangingDimensions() throws {
        let screenshot = try makeWhiteScreenshot(width: 64, height: 64)

        let result = try DesktopScreenshotTransformService.render(
            screenshot: screenshot,
            cropRect: nil,
            scale: 1.0,
            gridOverlay: nil,
            cursorOverlay: DesktopScreenshotCursorOverlayOptions(center: CGPoint(x: 20, y: 12), radius: 12)
        )

        #expect(result.width == 64)
        #expect(result.height == 64)
        #expect(!result.pngData.isEmpty)
    }

    @Test
    func renderAddsGridOverlayUsingTopLeftCoordinates() throws {
        let screenshot = try makeWhiteScreenshot(width: 64, height: 64)

        let result = try DesktopScreenshotTransformService.render(
            screenshot: screenshot,
            cropRect: nil,
            scale: 1.0,
            gridOverlay: DesktopScreenshotGridOverlayOptions(
                spacing: 16,
                coordinateOriginX: 0,
                coordinateOriginY: 0,
                coordinateWidthPx: 64,
                coordinateHeightPx: 64
            ),
            cursorOverlay: nil
        )

        #expect(result.width == 64)
        #expect(result.height == 64)
        #expect(!result.pngData.isEmpty)
    }

    @Test
    func convertTopLeftRectToDrawingSpaceFlipsY() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 80)
        let converted = DesktopScreenshotTransformService.convertTopLeftRectToDrawingSpace(
            CGRect(x: 8, y: 6, width: 20, height: 10),
            in: rect
        )

        #expect(converted.origin.x == 8)
        #expect(converted.origin.y == 64)
        #expect(converted.width == 20)
        #expect(converted.height == 10)
    }

    @Test
    func convertTopLeftPointToDrawingSpaceFlipsY() {
        let point = DesktopScreenshotTransformService.convertTopLeftPointToDrawingSpace(
            CGPoint(x: 20, y: 12),
            in: CGRect(x: 0, y: 0, width: 64, height: 64)
        )

        #expect(point.x == 20)
        #expect(point.y == 52)
    }

    private func makeScreenshot(width: Int, height: Int) throws -> OpenAICapturedScreenshot {
        try makeScreenshot(width: width, height: height) { width, height in
            NSColor.red.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: 20)).fill()
            NSColor.blue.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: height - 20, width: width, height: 20)).fill()
        }
    }

    private func makeWhiteScreenshot(width: Int, height: Int) throws -> OpenAICapturedScreenshot {
        try makeScreenshot(width: width, height: height) { _, _ in }
    }

    private func makeScreenshot(
        width: Int,
        height: Int,
        draw: (_ width: Int, _ height: Int) -> Void
    ) throws -> OpenAICapturedScreenshot {
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
        draw(width, height)
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

    private func colorAtTopLeft(in pngData: Data, x: Int, y: Int) -> NSColor? {
        guard let rep = NSBitmapImageRep(data: pngData) else {
            return nil
        }

        guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh else {
            return nil
        }

        return rep.colorAt(x: x, y: y)
    }
}

private extension NSColor {
    var isMostlyBlue: Bool {
        let color = usingColorSpace(.deviceRGB) ?? self
        return color.blueComponent > 0.7 && color.redComponent < 0.4 && color.greenComponent < 0.4
    }
}
