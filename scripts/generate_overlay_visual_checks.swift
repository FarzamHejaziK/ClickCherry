import AppKit
import Foundation

struct OpenAICapturedScreenshot {
    var width: Int
    var height: Int
    var captureWidthPx: Int
    var captureHeightPx: Int
    var coordinateSpaceWidthPx: Int
    var coordinateSpaceHeightPx: Int
    var coordinateSpaceOriginX: Int
    var coordinateSpaceOriginY: Int
    var mediaType: String
    var base64Data: String
    var byteCount: Int
}

@main
struct OverlayVisualCheckGenerator {
    static func main() throws {
        let outputDirectory = resolveOutputDirectory()
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let screenshot = try makeFixtureScreenshot(width: 256, height: 160)
        try writeBaseScreenshot(screenshot, to: outputDirectory.appendingPathComponent("01-base-fixture.png"))

        let fullCursor = try DesktopScreenshotTransformService.render(
            screenshot: screenshot,
            cropRect: nil,
            scale: 1.0,
            gridOverlay: nil,
            cursorOverlay: DesktopScreenshotCursorOverlayOptions(center: CGPoint(x: 208, y: 24), radius: 16)
        )
        try fullCursor.pngData.write(to: outputDirectory.appendingPathComponent("02-full-cursor-overlay.png"))

        let fullGrid = try DesktopScreenshotTransformService.render(
            screenshot: screenshot,
            cropRect: nil,
            scale: 1.0,
            gridOverlay: DesktopScreenshotGridOverlayOptions(
                spacing: 32,
                coordinateOriginX: 0,
                coordinateOriginY: 0,
                coordinateWidthPx: 256,
                coordinateHeightPx: 160
            ),
            cursorOverlay: nil
        )
        try fullGrid.pngData.write(to: outputDirectory.appendingPathComponent("03-full-grid-overlay.png"))

        let cropRect = CGRect(x: 160, y: 96, width: 80, height: 40)
        let cropGrid = try DesktopScreenshotTransformService.render(
            screenshot: screenshot,
            cropRect: cropRect,
            scale: 4.0,
            gridOverlay: DesktopScreenshotGridOverlayOptions(
                spacing: 16,
                coordinateOriginX: 160,
                coordinateOriginY: 96,
                coordinateWidthPx: 80,
                coordinateHeightPx: 40
            ),
            cursorOverlay: nil
        )
        try cropGrid.pngData.write(to: outputDirectory.appendingPathComponent("04-crop-grid-overlay.png"))

        let cropCursorAndGrid = try DesktopScreenshotTransformService.render(
            screenshot: screenshot,
            cropRect: cropRect,
            scale: 4.0,
            gridOverlay: DesktopScreenshotGridOverlayOptions(
                spacing: 16,
                coordinateOriginX: 160,
                coordinateOriginY: 96,
                coordinateWidthPx: 80,
                coordinateHeightPx: 40
            ),
            cursorOverlay: DesktopScreenshotCursorOverlayOptions(center: CGPoint(x: 208, y: 120), radius: 10)
        )
        try cropCursorAndGrid.pngData.write(to: outputDirectory.appendingPathComponent("05-crop-grid-and-cursor-overlay.png"))

        let notes = """
        Overlay visual checks
        =====================

        01-base-fixture.png
        - Synthetic reference image.
        - Yellow target square centered near (208,24).
        - Magenta target square centered near (208,120).
        - Cyan crop box from (160,96) size 80x40.

        02-full-cursor-overlay.png
        - Red cursor ring should sit on the yellow target square near the top-right.
        - It should not appear mirrored near the bottom.

        03-full-grid-overlay.png
        - Edge labels should increase downward from the top: 32, 64, 96, 128...
        - Vertical labels should align to 32, 64, 96... from the left.

        04-crop-grid-overlay.png
        - Cropped and scaled view of the cyan crop box.
        - Top edge labels should be in selected-display coordinates starting at 160 on x and 96 on y.

        05-crop-grid-and-cursor-overlay.png
        - Same cropped view with the red cursor ring centered on the magenta target.
        """
        try notes.write(to: outputDirectory.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)

        print(outputDirectory.path)
    }

    private static func resolveOutputDirectory() -> URL {
        if CommandLine.arguments.count > 1 {
            return URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        }
        return URL(fileURLWithPath: "/tmp/clickcherry-overlay-visual-checks", isDirectory: true)
    }

    private static func writeBaseScreenshot(_ screenshot: OpenAICapturedScreenshot, to url: URL) throws {
        guard let data = Data(base64Encoded: screenshot.base64Data) else {
            throw NSError(domain: "OverlayVisualCheckGenerator", code: 1)
        }
        try data.write(to: url)
    }

    private static func makeFixtureScreenshot(width: Int, height: Int) throws -> OpenAICapturedScreenshot {
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
            throw NSError(domain: "OverlayVisualCheckGenerator", code: 2)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        fillTopLeftRect(x: 0, y: 0, width: width, height: height, in: height, color: NSColor.white)
        fillTopLeftRect(x: 0, y: 0, width: width, height: 24, in: height, color: NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.88, alpha: 1))
        fillTopLeftRect(x: 0, y: height - 24, width: width, height: 24, in: height, color: NSColor(calibratedRed: 0.26, green: 0.58, blue: 0.30, alpha: 1))
        fillTopLeftRect(x: 24, y: 40, width: 104, height: 52, in: height, color: NSColor(calibratedWhite: 0.9, alpha: 1))
        fillTopLeftRect(x: 152, y: 36, width: 80, height: 32, in: height, color: NSColor(calibratedRed: 0.93, green: 0.93, blue: 0.82, alpha: 1))
        strokeTopLeftRect(x: 160, y: 96, width: 80, height: 40, in: height, color: NSColor.systemCyan, lineWidth: 3)

        fillCenteredMarker(at: CGPoint(x: 208, y: 24), size: 12, canvasHeight: height, color: NSColor.systemYellow)
        fillCenteredMarker(at: CGPoint(x: 208, y: 120), size: 12, canvasHeight: height, color: NSColor.systemPink)
        drawText("Top target", atTopLeft: CGPoint(x: 160, y: 8), canvasHeight: height)
        drawText("Crop box", atTopLeft: CGPoint(x: 166, y: 100), canvasHeight: height)
        drawText("Lower target", atTopLeft: CGPoint(x: 150, y: 136), canvasHeight: height)

        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "OverlayVisualCheckGenerator", code: 3)
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

    private static func fillCenteredMarker(at point: CGPoint, size: CGFloat, canvasHeight: Int, color: NSColor) {
        fillTopLeftRect(
            x: Int((point.x - size / 2).rounded()),
            y: Int((point.y - size / 2).rounded()),
            width: Int(size.rounded()),
            height: Int(size.rounded()),
            in: canvasHeight,
            color: color
        )
    }

    private static func fillTopLeftRect(x: Int, y: Int, width: Int, height: Int, in canvasHeight: Int, color: NSColor) {
        color.setFill()
        let rect = CGRect(
            x: x,
            y: canvasHeight - y - height,
            width: width,
            height: height
        )
        NSBezierPath(rect: rect).fill()
    }

    private static func strokeTopLeftRect(x: Int, y: Int, width: Int, height: Int, in canvasHeight: Int, color: NSColor, lineWidth: CGFloat) {
        color.setStroke()
        let rect = CGRect(
            x: x,
            y: canvasHeight - y - height,
            width: width,
            height: height
        )
        let path = NSBezierPath(rect: rect)
        path.lineWidth = lineWidth
        path.stroke()
    }

    private static func drawText(_ text: String, atTopLeft origin: CGPoint, canvasHeight: Int) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.black
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = attributed.size()
        let rect = CGRect(
            x: origin.x,
            y: CGFloat(canvasHeight) - origin.y - size.height,
            width: size.width,
            height: size.height
        )
        attributed.draw(in: rect)
    }
}
