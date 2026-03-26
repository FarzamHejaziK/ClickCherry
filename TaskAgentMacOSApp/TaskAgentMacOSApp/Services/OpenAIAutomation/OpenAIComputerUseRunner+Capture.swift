import AppKit
import ApplicationServices
import Foundation
import ImageIO
import UniformTypeIdentifiers

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
        guard coordinateSpaceWidthPx > 0, coordinateSpaceHeightPx > 0 else {
            return nil
        }
        let centerX = coordinateSpaceOriginX + (coordinateSpaceWidthPx / 2)
        let centerY = coordinateSpaceOriginY + (coordinateSpaceHeightPx / 2)
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

    func userTextAndImageInput(text: String, screenshot: OpenAICapturedScreenshot) -> [String: Any] {
        [
            "role": "user",
            "content": [
                [
                    "type": "input_text",
                    "text": text
                ],
                [
                    "type": "input_image",
                    "image_url": imageDataURL(for: screenshot)
                ]
            ]
        ]
    }

    func imageDataURL(for screenshot: OpenAICapturedScreenshot) -> String {
        "data:\(screenshot.mediaType);base64,\(screenshot.base64Data)"
    }

    func captureScreenshotForLLM(source: LLMScreenshotSource) throws -> OpenAICapturedScreenshot {
        let screenshot = try screenshotProvider()
        // Never retain screenshots in memory logs unless an explicit sink is provided.
        if screenshotLogSink != nil, let encodedData = Data(base64Encoded: screenshot.base64Data) {
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
        return screenshot
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

        let optimizedImage = optimizeScreenshotPayload(capture.pngData)
        return OpenAICapturedScreenshot(
            width: capture.width,
            height: capture.height,
            captureWidthPx: capture.width,
            captureHeightPx: capture.height,
            coordinateSpaceWidthPx: coordSpaceW,
            coordinateSpaceHeightPx: coordSpaceH,
            coordinateSpaceOriginX: originX,
            coordinateSpaceOriginY: originY,
            mediaType: optimizedImage.mediaType,
            base64Data: optimizedImage.data.base64EncodedString(),
            byteCount: optimizedImage.data.count
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

        let optimizedImage = optimizeScreenshotPayload(capture.pngData)
        return OpenAICapturedScreenshot(
            width: capture.width,
            height: capture.height,
            captureWidthPx: capture.width,
            captureHeightPx: capture.height,
            coordinateSpaceWidthPx: coordSpaceW,
            coordinateSpaceHeightPx: coordSpaceH,
            coordinateSpaceOriginX: originX,
            coordinateSpaceOriginY: originY,
            mediaType: optimizedImage.mediaType,
            base64Data: optimizedImage.data.base64EncodedString(),
            byteCount: optimizedImage.data.count
        )
    }

    nonisolated static func optimizeScreenshotPayload(_ pngData: Data) -> (data: Data, mediaType: String) {
        guard
            let imageSource = CGImageSourceCreateWithData(pngData as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            return (pngData, "image/png")
        }

        let output = NSMutableData()
        let webpTypeIdentifier = UTType(filenameExtension: "webp")?.identifier ?? "public.webp"
        guard let destination = CGImageDestinationCreateWithData(
            output,
            webpTypeIdentifier as CFString,
            1,
            nil
        ) else {
            return (pngData, "image/png")
        }

        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.84
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return (pngData, "image/png")
        }

        let webpData = output as Data
        // Keep PNG when WebP is unexpectedly larger.
        guard webpData.count < pngData.count else {
            return (pngData, "image/png")
        }
        return (webpData, "image/webp")
    }
}
