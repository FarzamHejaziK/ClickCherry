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
    var coordinateOriginX: Int
    var coordinateOriginY: Int
    var coordinateWidthPx: Int
    var coordinateHeightPx: Int
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
                options: gridOverlay
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

    private static func drawGridOverlay(in rect: CGRect, options: DesktopScreenshotGridOverlayOptions) {
        let spacing = max(minimumGridSpacing, options.spacing)
        guard options.coordinateWidthPx > 0, options.coordinateHeightPx > 0 else {
            return
        }

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

        let pixelsPerCoordinateX = rect.width / CGFloat(options.coordinateWidthPx)
        let pixelsPerCoordinateY = rect.height / CGFloat(options.coordinateHeightPx)
        let minXCoord = options.coordinateOriginX
        let maxXCoord = options.coordinateOriginX + max(0, options.coordinateWidthPx - 1)
        let minYCoord = options.coordinateOriginY
        let maxYCoord = options.coordinateOriginY + max(0, options.coordinateHeightPx - 1)

        for xCoord in stride(from: firstVisibleGridCoordinate(atOrAfter: minXCoord, spacing: spacing), through: maxXCoord, by: spacing) {
            let pointX = rect.minX + (CGFloat(xCoord - options.coordinateOriginX) * pixelsPerCoordinateX)
            drawLine(
                from: CGPoint(x: pointX, y: rect.minY),
                to: CGPoint(x: pointX, y: rect.maxY),
                in: rect,
                underlayColor: underlayColor,
                overlayColor: overlayColor
            )
            drawLabel(
                text: "\(xCoord)",
                origin: CGPoint(x: min(max(rect.minX + 4, pointX - 24), rect.maxX - 52), y: rect.minY + 6),
                in: rect,
                backgroundColor: labelBackground,
                attributes: attributes
            )
        }

        for yCoord in stride(from: firstVisibleGridCoordinate(atOrAfter: minYCoord, spacing: spacing), through: maxYCoord, by: spacing) {
            let pointY = rect.minY + (CGFloat(yCoord - options.coordinateOriginY) * pixelsPerCoordinateY)
            drawLine(
                from: CGPoint(x: rect.minX, y: pointY),
                to: CGPoint(x: rect.maxX, y: pointY),
                in: rect,
                underlayColor: underlayColor,
                overlayColor: overlayColor
            )
            drawLabel(
                text: "\(yCoord)",
                origin: CGPoint(x: rect.minX + 6, y: min(max(rect.minY + 4, pointY - 10), rect.maxY - 22)),
                in: rect,
                backgroundColor: labelBackground,
                attributes: attributes
            )
        }
    }

    private static func firstVisibleGridCoordinate(atOrAfter value: Int, spacing: Int) -> Int {
        guard spacing > 0 else { return value }
        let remainder = value % spacing
        if remainder == 0 {
            return value
        }
        if remainder > 0 {
            return value + (spacing - remainder)
        }
        return value - remainder
    }

    private static func drawCursorOverlay(in rect: CGRect, center: CGPoint, radius: CGFloat) {
        let drawingCenter = convertTopLeftPointToDrawingSpace(center, in: rect)
        guard rect.contains(drawingCenter) else { return }

        let outerRect = CGRect(
            x: drawingCenter.x - radius,
            y: drawingCenter.y - radius,
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
            x: drawingCenter.x - dotRadius,
            y: drawingCenter.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        )
        NSColor(calibratedRed: 1.0, green: 0.12, blue: 0.12, alpha: 0.95).setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }

    private static func drawLine(
        from start: CGPoint,
        to end: CGPoint,
        in rect: CGRect,
        underlayColor: NSColor,
        overlayColor: NSColor
    ) {
        let drawingStart = convertTopLeftPointToDrawingSpace(start, in: rect)
        let drawingEnd = convertTopLeftPointToDrawingSpace(end, in: rect)

        let underlay = NSBezierPath()
        underlay.lineWidth = 3.0
        underlay.lineCapStyle = .round
        underlay.move(to: drawingStart)
        underlay.line(to: drawingEnd)
        underlayColor.setStroke()
        underlay.stroke()

        let overlay = NSBezierPath()
        overlay.lineWidth = 1.0
        overlay.lineCapStyle = .round
        overlay.move(to: drawingStart)
        overlay.line(to: drawingEnd)
        overlayColor.setStroke()
        overlay.stroke()
    }

    private static func drawLabel(
        text: String,
        origin: CGPoint,
        in rect: CGRect,
        backgroundColor: NSColor,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = attributed.size()
        let drawingRect = convertTopLeftRectToDrawingSpace(
            CGRect(
                x: origin.x,
                y: origin.y,
                width: size.width + 12,
                height: size.height + 6
            ),
            in: rect
        )
        backgroundColor.setFill()
        NSBezierPath(roundedRect: drawingRect, xRadius: 6, yRadius: 6).fill()
        attributed.draw(in: CGRect(
            x: drawingRect.minX + 6,
            y: drawingRect.minY + 3,
            width: size.width,
            height: size.height
        ))
    }

    static func convertTopLeftPointToDrawingSpace(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: point.x, y: rect.maxY - point.y)
    }

    static func convertTopLeftRectToDrawingSpace(_ topLeftRect: CGRect, in rect: CGRect) -> CGRect {
        CGRect(
            x: topLeftRect.origin.x,
            y: rect.maxY - topLeftRect.maxY,
            width: topLeftRect.width,
            height: topLeftRect.height
        )
    }
}
