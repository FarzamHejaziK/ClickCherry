import AppKit
import ApplicationServices
import Foundation

extension OpenAIComputerUseRunner {
    func mapToToolCoordinates(x: Int, y: Int) -> (x: Int, y: Int) {
        // Incoming cursor coordinates are in global screen space; convert to local display space.
        let localX = x - coordinateSpaceOriginX
        let localY = y - coordinateSpaceOriginY

        let invScaleX = coordinateScaleX == 0 ? 1.0 : coordinateScaleX
        let invScaleY = coordinateScaleY == 0 ? 1.0 : coordinateScaleY
        let scaledX = Int((Double(localX) / invScaleX).rounded())
        let scaledY = Int((Double(localY) / invScaleY).rounded())

        if toolDisplayWidthPx > 0, toolDisplayHeightPx > 0 {
            return (
                max(0, min(toolDisplayWidthPx - 1, scaledX)),
                max(0, min(toolDisplayHeightPx - 1, scaledY))
            )
        }

        return (scaledX, scaledY)
    }

    func mapToScreenCoordinates(x: Int, y: Int) -> (x: Int, y: Int) {
        let scaledX = Int((Double(x) * coordinateScaleX).rounded())
        let scaledY = Int((Double(y) * coordinateScaleY).rounded())

        if coordinateSpaceWidthPx > 0, coordinateSpaceHeightPx > 0 {
            let clampedX = max(0, min(coordinateSpaceWidthPx - 1, scaledX))
            let clampedY = max(0, min(coordinateSpaceHeightPx - 1, scaledY))
            if clampedX != scaledX || clampedY != scaledY {
                recordTrace(
                    kind: .info,
                    "Clamped tool coordinates from (\(scaledX), \(scaledY)) to (\(clampedX), \(clampedY)) for coordSpace=\(coordinateSpaceWidthPx)x\(coordinateSpaceHeightPx)."
                )
            }
            // Convert from local display space to global space so CGEvent injection targets the correct monitor.
            return (clampedX + coordinateSpaceOriginX, clampedY + coordinateSpaceOriginY)
        }

        return (scaledX + coordinateSpaceOriginX, scaledY + coordinateSpaceOriginY)
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

        let scaleX = screenshot.width > 0 ? Double(screenshot.coordinateSpaceWidthPx) / Double(screenshot.width) : 1.0
        let scaleY = screenshot.height > 0 ? Double(screenshot.coordinateSpaceHeightPx) / Double(screenshot.height) : 1.0
        let localX = cursor.x - screenshot.coordinateSpaceOriginX
        let localY = cursor.y - screenshot.coordinateSpaceOriginY
        let imageX = Int((Double(localX) / (scaleX == 0 ? 1.0 : scaleX)).rounded())
        let imageY = Int((Double(localY) / (scaleY == 0 ? 1.0 : scaleY)).rounded())

        guard screenshot.width > 0, screenshot.height > 0 else {
            return (imageX, imageY)
        }

        return (
            max(0, min(screenshot.width - 1, imageX)),
            max(0, min(screenshot.height - 1, imageY))
        )
    }

    func visualCoordinateContextValues(for screenshot: OpenAICapturedScreenshot) -> [String] {
        var lines = [
            "IMAGE_COORDINATE_SYSTEM: origin=(0,0) is top-left of the screenshot, x increases rightward, y increases downward.",
            "TOP_LEFT: (0, 0)",
            "TOP_RIGHT: (\(max(0, screenshot.width - 1)), 0)",
            "BOTTOM_LEFT: (0, \(max(0, screenshot.height - 1)))",
            "BOTTOM_RIGHT: (\(max(0, screenshot.width - 1)), \(max(0, screenshot.height - 1)))"
        ]
        if let cursor = currentCursorImagePoint(in: screenshot) {
            lines.insert("CURRENT_CURSOR: (\(cursor.x), \(cursor.y))", at: 0)
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
