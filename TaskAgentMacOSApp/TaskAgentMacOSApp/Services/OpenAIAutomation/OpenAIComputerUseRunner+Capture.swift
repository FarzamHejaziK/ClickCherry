import AppKit
import ApplicationServices
import Foundation

struct OpenAICursorContext: Equatable {
    var x: Int
    var y: Int
    var isVisibleInImage: Bool
}

extension OpenAIComputerUseRunner {
    func selectedDisplayLocalPoint(fromScreenX x: Int, y: Int) -> (x: Int, y: Int) {
        (
            x - selectedDisplayCoordinateSpaceOriginX,
            y - selectedDisplayCoordinateSpaceOriginY
        )
    }

    func selectedDisplayLocalRect(for screenshot: OpenAICapturedScreenshot) -> CGRect {
        CGRect(
            x: screenshot.coordinateSpaceOriginX - selectedDisplayCoordinateSpaceOriginX,
            y: screenshot.coordinateSpaceOriginY - selectedDisplayCoordinateSpaceOriginY,
            width: screenshot.coordinateSpaceWidthPx,
            height: screenshot.coordinateSpaceHeightPx
        )
    }

    func mapSelectedDisplayRectToImageRect(
        _ rect: CGRect,
        in screenshot: OpenAICapturedScreenshot
    ) -> CGRect {
        let scaleX = screenshot.coordinateSpaceWidthPx > 0
            ? Double(screenshot.width) / Double(screenshot.coordinateSpaceWidthPx)
            : 1.0
        let scaleY = screenshot.coordinateSpaceHeightPx > 0
            ? Double(screenshot.height) / Double(screenshot.coordinateSpaceHeightPx)
            : 1.0

        return CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).integral
    }

    func mapToToolCoordinates(x: Int, y: Int) -> (x: Int, y: Int) {
        selectedDisplayLocalPoint(fromScreenX: x, y: y)
    }

    func mapToScreenCoordinates(x: Int, y: Int) -> (x: Int, y: Int) {
        if selectedDisplayCoordinateSpaceWidthPx > 0, selectedDisplayCoordinateSpaceHeightPx > 0 {
            let clampedX = max(0, min(selectedDisplayCoordinateSpaceWidthPx - 1, x))
            let clampedY = max(0, min(selectedDisplayCoordinateSpaceHeightPx - 1, y))
            if clampedX != x || clampedY != y {
                recordTrace(
                    kind: .info,
                    "Clamped display coordinates from (\(x), \(y)) to (\(clampedX), \(clampedY)) for selectedDisplay=\(selectedDisplayCoordinateSpaceWidthPx)x\(selectedDisplayCoordinateSpaceHeightPx)."
                )
            }
            return (
                clampedX + selectedDisplayCoordinateSpaceOriginX,
                clampedY + selectedDisplayCoordinateSpaceOriginY
            )
        }

        return (
            x + selectedDisplayCoordinateSpaceOriginX,
            y + selectedDisplayCoordinateSpaceOriginY
        )
    }

    func targetDisplayCenterPoint() -> (x: Int, y: Int)? {
        guard selectedDisplayCoordinateSpaceWidthPx > 0, selectedDisplayCoordinateSpaceHeightPx > 0 else {
            return nil
        }
        let centerX = selectedDisplayCoordinateSpaceOriginX + (selectedDisplayCoordinateSpaceWidthPx / 2)
        let centerY = selectedDisplayCoordinateSpaceOriginY + (selectedDisplayCoordinateSpaceHeightPx / 2)
        return (centerX, centerY)
    }

    func anchorInteractionTarget(
        executor: any DesktopActionExecutor,
        reason: String,
        performClick: Bool
    ) {
        guard let center = targetDisplayCenterPoint() else {
            return
        }

        do {
            try executor.moveMouse(x: center.x, y: center.y)
            if performClick {
                try executor.click(x: center.x, y: center.y)
            }
            let clickLabel = performClick ? " + click" : ""
            recordTrace(kind: .info, "Anchored pointer to selected display center at (\(center.x), \(center.y))\(clickLabel) [\(reason)].")
        } catch {
            recordTrace(kind: .error, "Failed to anchor pointer to selected display [\(reason)]: \(error.localizedDescription)")
        }
    }

    func userTextAndImageInput(
        text: String,
        screenshot: OpenAICapturedScreenshot,
        source: LLMScreenshotSource
    ) -> [String: Any] {
        recordScreenshotSentToLLM(screenshot, source: source)

        return [
            "role": "user",
            "content": [
                [
                    "type": "input_text",
                    "text": text
                ],
                [
                    "type": "input_image",
                    "image_url": imageDataURL(for: screenshot),
                    "detail": "original"
                ]
            ]
        ]
    }

    func recordScreenshotSentToLLM(
        _ screenshot: OpenAICapturedScreenshot,
        source: LLMScreenshotSource
    ) {
        guard screenshotLogSink != nil, let encodedData = Data(base64Encoded: screenshot.base64Data) else {
            return
        }

        screenshotLogSink?(LLMScreenshotLogEntry(
            source: source,
            mediaType: screenshot.mediaType,
            width: screenshot.width,
            height: screenshot.height,
            captureWidthPx: screenshot.captureWidthPx,
            captureHeightPx: screenshot.captureHeightPx,
            coordinateSpaceWidthPx: screenshot.coordinateSpaceWidthPx,
            coordinateSpaceHeightPx: screenshot.coordinateSpaceHeightPx,
            rawByteCount: screenshot.byteCount,
            base64ByteCount: screenshot.base64Data.utf8.count,
            imageData: encodedData
        ))
    }

    func imageDataURL(for screenshot: OpenAICapturedScreenshot) -> String {
        "data:\(screenshot.mediaType);base64,\(screenshot.base64Data)"
    }

    func currentCursorImagePoint(in screenshot: OpenAICapturedScreenshot) -> (x: Int, y: Int)? {
        guard let cursor = cursorPositionProvider() else { return nil }

        let representedRect = CGRect(
            x: screenshot.coordinateSpaceOriginX,
            y: screenshot.coordinateSpaceOriginY,
            width: screenshot.coordinateSpaceWidthPx,
            height: screenshot.coordinateSpaceHeightPx
        )
        guard representedRect.contains(CGPoint(x: cursor.x, y: cursor.y)) else {
            return nil
        }

        let scaleX = screenshot.width > 0 ? Double(screenshot.coordinateSpaceWidthPx) / Double(screenshot.width) : 1.0
        let scaleY = screenshot.height > 0 ? Double(screenshot.coordinateSpaceHeightPx) / Double(screenshot.height) : 1.0
        let localX = cursor.x - screenshot.coordinateSpaceOriginX
        let localY = cursor.y - screenshot.coordinateSpaceOriginY
        let imageX = Int((Double(localX) / (scaleX == 0 ? 1.0 : scaleX)).rounded())
        let imageY = Int((Double(localY) / (scaleY == 0 ? 1.0 : scaleY)).rounded())

        guard screenshot.width > 0, screenshot.height > 0 else {
            return (imageX, imageY)
        }

        guard
            imageX >= 0,
            imageY >= 0,
            imageX < screenshot.width,
            imageY < screenshot.height
        else {
            return nil
        }

        return (imageX, imageY)
    }

    func currentCursorContext(for screenshot: OpenAICapturedScreenshot) -> OpenAICursorContext? {
        guard let cursor = cursorPositionProvider() else { return nil }

        let localCursor = selectedDisplayLocalPoint(fromScreenX: cursor.x, y: cursor.y)
        let localRect = selectedDisplayLocalRect(for: screenshot)
        return OpenAICursorContext(
            x: localCursor.x,
            y: localCursor.y,
            isVisibleInImage: localRect.contains(CGPoint(x: localCursor.x, y: localCursor.y))
        )
    }

    func visualCoordinateContextValues(for screenshot: OpenAICapturedScreenshot) -> [String] {
        let localRect = selectedDisplayLocalRect(for: screenshot)
        let originX = Int(localRect.origin.x.rounded())
        let originY = Int(localRect.origin.y.rounded())
        let maxX = originX + max(0, screenshot.coordinateSpaceWidthPx - 1)
        let maxY = originY + max(0, screenshot.coordinateSpaceHeightPx - 1)

        var lines = [
            "COORDINATE_SYSTEM: All screenshot and action coordinates use the selected display coordinate system; crops and zoom do not change coordinate meaning.",
            "TOP_LEFT: (\(originX), \(originY))",
            "TOP_RIGHT: (\(maxX), \(originY))",
            "BOTTOM_LEFT: (\(originX), \(maxY))",
            "BOTTOM_RIGHT: (\(maxX), \(maxY))"
        ]
        if let cursor = currentCursorContext(for: screenshot) {
            if cursor.isVisibleInImage {
                lines.insert("CURRENT_CURSOR: (\(cursor.x), \(cursor.y))", at: 0)
            } else {
                lines.insert("CURRENT_CURSOR: outside current image; actual=(\(cursor.x), \(cursor.y))", at: 0)
            }
        }
        return lines
    }

    func appendVisualCoordinateContext(to text: String, screenshot: OpenAICapturedScreenshot) -> String {
        let context = visualCoordinateContextValues(for: screenshot).joined(separator: "\n")
        return "\(text)\n\n\(context)"
    }

    func captureScreenshotForLLM(source: LLMScreenshotSource) throws -> OpenAICapturedScreenshot {
        _ = source
        return try screenshotProvider()
    }

    nonisolated static func currentCursorPosition() -> (x: Int, y: Int)? {
        if let event = CGEvent(source: nil) {
            let point = event.location
            return (Int(point.x.rounded()), Int(point.y.rounded()))
        }
        let point = NSEvent.mouseLocation
        return (Int(point.x.rounded()), Int(point.y.rounded()))
    }

    nonisolated static func captureMainDisplayScreenshot() throws -> OpenAICapturedScreenshot {
        try captureMainDisplayScreenshot(excludingWindowNumbers: [])
    }

    nonisolated static func captureMainDisplayScreenshot(excludingWindowNumber: Int?) throws -> OpenAICapturedScreenshot {
        try captureMainDisplayScreenshot(excludingWindowNumbers: excludingWindowNumber.flatMap { [$0] } ?? [])
    }

    nonisolated static func captureMainDisplayScreenshot(excludingWindowNumbers: [Int]) throws -> OpenAICapturedScreenshot {
        let mainDisplayID = CGMainDisplayID()
        let bounds = CGDisplayBounds(mainDisplayID)
        let coordSpaceW = max(1, Int(bounds.width.rounded()))
        let coordSpaceH = max(1, Int(bounds.height.rounded()))
        let originX = Int(bounds.origin.x.rounded())
        let originY = Int(bounds.origin.y.rounded())

        let capture: DesktopScreenshotCapture
        do {
            capture = try DesktopScreenshotService.captureMainDisplayPNG(excludingWindowNumbers: excludingWindowNumbers)
        } catch {
            throw OpenAIExecutionPlannerError.screenshotCaptureFailed
        }

        return OpenAICapturedScreenshot(
            width: capture.width,
            height: capture.height,
            captureWidthPx: capture.width,
            captureHeightPx: capture.height,
            coordinateSpaceWidthPx: coordSpaceW,
            coordinateSpaceHeightPx: coordSpaceH,
            coordinateSpaceOriginX: originX,
            coordinateSpaceOriginY: originY,
            mediaType: "image/png",
            base64Data: capture.pngData.base64EncodedString(),
            byteCount: capture.pngData.count
        )
    }

    nonisolated static func captureDisplayScreenshot(displayIndex: Int, excludingWindowNumber: Int?) throws -> OpenAICapturedScreenshot {
        try captureDisplayScreenshot(displayIndex: displayIndex, excludingWindowNumbers: excludingWindowNumber.flatMap { [$0] } ?? [])
    }

    nonisolated static func captureDisplayScreenshot(displayIndex: Int, excludingWindowNumbers: [Int]) throws -> OpenAICapturedScreenshot {
        guard let displayID = ScreenDisplayIndexService.cgDisplayIDForScreencaptureDisplayIndex(displayIndex) else {
            throw OpenAIExecutionPlannerError.screenshotCaptureFailed
        }

        let bounds = CGDisplayBounds(displayID)
        let coordSpaceW = max(1, Int(bounds.width.rounded()))
        let coordSpaceH = max(1, Int(bounds.height.rounded()))
        let originX = Int(bounds.origin.x.rounded())
        let originY = Int(bounds.origin.y.rounded())

        let capture: DesktopScreenshotCapture
        do {
            capture = try DesktopScreenshotService.captureDisplayPNG(displayID: displayID, excludingWindowNumbers: excludingWindowNumbers)
        } catch {
            throw OpenAIExecutionPlannerError.screenshotCaptureFailed
        }

        return OpenAICapturedScreenshot(
            width: capture.width,
            height: capture.height,
            captureWidthPx: capture.width,
            captureHeightPx: capture.height,
            coordinateSpaceWidthPx: coordSpaceW,
            coordinateSpaceHeightPx: coordSpaceH,
            coordinateSpaceOriginX: originX,
            coordinateSpaceOriginY: originY,
            mediaType: "image/png",
            base64Data: capture.pngData.base64EncodedString(),
            byteCount: capture.pngData.count
        )
    }
}
