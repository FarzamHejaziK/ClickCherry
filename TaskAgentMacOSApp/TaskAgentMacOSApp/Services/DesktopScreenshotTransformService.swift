import AppKit
import Foundation

enum DesktopScreenshotTransformError: Error, Equatable {
    case invalidImageData
    case invalidCropRect
    case renderFailed
    case encodeFailed
}

struct DesktopScreenshotGridOverlayOptions: Equatable {
    var spacing: Int
}

struct DesktopScreenshotCursorOverlayOptions: Equatable {
    var center: CGPoint
    var radius: CGFloat
}

struct DesktopScreenshotTransformResult: Equatable {
    var pngData: Data
    var width: Int
    var height: Int
}

struct DesktopScreenshotTransformService {
    private static let minimumGridSpacing = 16

    static func render(
        screenshot: OpenAICapturedScreenshot,
        cropRect: CGRect?,
        scale: Double,
        gridOverlay: DesktopScreenshotGridOverlayOptions?,
        cursorOverlay: DesktopScreenshotCursorOverlayOptions?
    ) throws -> DesktopScreenshotTransformResult {
        guard
            let sourceData = Data(base64Encoded: screenshot.base64Data),
            let image = NSImage(data: sourceData)
        else {
            throw DesktopScreenshotTransformError.invalidImageData
        }

        let imageRect = CGRect(x: 0, y: 0, width: screenshot.width, height: screenshot.height)
        let visibleCrop = (cropRect ?? imageRect).intersection(imageRect).integral
        guard !visibleCrop.isNull, visibleCrop.width >= 1, visibleCrop.height >= 1 else {
            throw DesktopScreenshotTransformError.invalidCropRect
        }

        let resolvedScale = max(1.0, scale)
        let outputWidth = max(1, Int((visibleCrop.width * resolvedScale).rounded()))
        let outputHeight = max(1, Int((visibleCrop.height * resolvedScale).rounded()))

        guard
            let bitmapRep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: outputWidth,
                pixelsHigh: outputHeight,
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
            throw DesktopScreenshotTransformError.renderFailed
        }

        let destinationRect = CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight)
        let sourceRect = CGRect(
            x: visibleCrop.origin.x,
            y: CGFloat(screenshot.height) - visibleCrop.maxY,
            width: visibleCrop.width,
            height: visibleCrop.height
        )

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.clear.setFill()
        destinationRect.fill(using: .copy)
        image.draw(
            in: destinationRect,
            from: sourceRect,
            operation: .copy,
            fraction: 1.0,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        if let gridOverlay {
            drawGridOverlay(
                in: destinationRect,
                spacing: max(minimumGridSpacing, Int((Double(gridOverlay.spacing) * resolvedScale).rounded()))
            )
        }

        if let cursorOverlay {
            let cursorCenter = CGPoint(
                x: (cursorOverlay.center.x - visibleCrop.origin.x) * resolvedScale,
                y: (cursorOverlay.center.y - visibleCrop.origin.y) * resolvedScale
            )
            drawCursorOverlay(
                in: destinationRect,
                center: cursorCenter,
                radius: cursorOverlay.radius * resolvedScale
            )
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw DesktopScreenshotTransformError.encodeFailed
        }

        return DesktopScreenshotTransformResult(
            pngData: pngData,
            width: outputWidth,
            height: outputHeight
        )
    }

    private static func drawGridOverlay(in rect: CGRect, spacing: Int) {
        let underlayColor = NSColor(calibratedWhite: 0.0, alpha: 0.65)
        let overlayColor = NSColor(calibratedRed: 1.0, green: 0.25, blue: 0.25, alpha: 0.9)
        let labelBackground = NSColor(calibratedWhite: 0.0, alpha: 0.7)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]

        for x in stride(from: 0, through: Int(rect.width.rounded()), by: spacing) {
            let pointX = CGFloat(x)
            drawLine(
                from: CGPoint(x: pointX, y: rect.minY),
                to: CGPoint(x: pointX, y: rect.maxY),
                underlayColor: underlayColor,
                overlayColor: overlayColor
            )
            drawLabel(
                text: "\(x)",
                origin: CGPoint(x: min(max(rect.minX + 4, pointX - 24), rect.maxX - 52), y: rect.minY + 6),
                backgroundColor: labelBackground,
                attributes: attributes
            )
        }

        for y in stride(from: 0, through: Int(rect.height.rounded()), by: spacing) {
            let pointY = CGFloat(y)
            drawLine(
                from: CGPoint(x: rect.minX, y: pointY),
                to: CGPoint(x: rect.maxX, y: pointY),
                underlayColor: underlayColor,
                overlayColor: overlayColor
            )
            drawLabel(
                text: "\(y)",
                origin: CGPoint(x: rect.minX + 6, y: min(max(rect.minY + 4, pointY - 10), rect.maxY - 22)),
                backgroundColor: labelBackground,
                attributes: attributes
            )
        }
    }

    private static func drawCursorOverlay(in rect: CGRect, center: CGPoint, radius: CGFloat) {
        guard rect.contains(center) else { return }

        let outerRect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        NSColor(calibratedRed: 1.0, green: 0.15, blue: 0.15, alpha: 0.22).setFill()
        NSBezierPath(ovalIn: outerRect).fill()

        NSColor(calibratedRed: 1.0, green: 0.15, blue: 0.15, alpha: 0.9).setStroke()
        let ring = NSBezierPath(ovalIn: outerRect)
        ring.lineWidth = 2.0
        ring.stroke()

        let dotRadius: CGFloat = max(3, radius * 0.18)
        let dotRect = CGRect(
            x: center.x - dotRadius,
            y: center.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        )
        NSColor(calibratedRed: 1.0, green: 0.12, blue: 0.12, alpha: 0.95).setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }

    private static func drawLine(from start: CGPoint, to end: CGPoint, underlayColor: NSColor, overlayColor: NSColor) {
        let underlay = NSBezierPath()
        underlay.lineWidth = 3.0
        underlay.lineCapStyle = .round
        underlay.move(to: start)
        underlay.line(to: end)
        underlayColor.setStroke()
        underlay.stroke()

        let overlay = NSBezierPath()
        overlay.lineWidth = 1.0
        overlay.lineCapStyle = .round
        overlay.move(to: start)
        overlay.line(to: end)
        overlayColor.setStroke()
        overlay.stroke()
    }

    private static func drawLabel(
        text: String,
        origin: CGPoint,
        backgroundColor: NSColor,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = attributed.size()
        let rect = CGRect(
            x: origin.x,
            y: origin.y,
            width: size.width + 12,
            height: size.height + 6
        )
        backgroundColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        attributed.draw(in: CGRect(x: rect.minX + 6, y: rect.minY + 3, width: size.width, height: size.height))
    }
}
