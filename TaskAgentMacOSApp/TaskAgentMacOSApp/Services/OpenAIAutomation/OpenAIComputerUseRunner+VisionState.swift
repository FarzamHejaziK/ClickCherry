import CoreGraphics
import Foundation

enum OpenAIScreenshotMode: String {
    case full
    case crop
    case current
}

enum OpenAIScreenshotOverlay: String {
    case none
    case grid
}

struct OpenAIVisionViewState: Equatable {
    var mode: OpenAIScreenshotMode
    var overlay: OpenAIScreenshotOverlay
    var zoomScale: Double
    var gridSpacing: Int?
    var imageWidth: Int
    var imageHeight: Int
    var coordinateSpaceWidthPx: Int
    var coordinateSpaceHeightPx: Int
    var coordinateSpaceOriginX: Int
    var coordinateSpaceOriginY: Int

    var scaleX: Double {
        imageWidth > 0 ? Double(coordinateSpaceWidthPx) / Double(imageWidth) : 1.0
    }

    var scaleY: Double {
        imageHeight > 0 ? Double(coordinateSpaceHeightPx) / Double(imageHeight) : 1.0
    }

    var screenRect: CGRect {
        CGRect(
            x: coordinateSpaceOriginX,
            y: coordinateSpaceOriginY,
            width: coordinateSpaceWidthPx,
            height: coordinateSpaceHeightPx
        )
    }

    func mapImagePointToScreen(x: Int, y: Int) -> (x: Int, y: Int) {
        let screenX = coordinateSpaceOriginX + Int((Double(x) * scaleX).rounded())
        let screenY = coordinateSpaceOriginY + Int((Double(y) * scaleY).rounded())
        return (screenX, screenY)
    }

    func mapScreenPointToImage(x: Int, y: Int) -> (x: Int, y: Int) {
        let localX = x - coordinateSpaceOriginX
        let localY = y - coordinateSpaceOriginY
        let imageX = Int((Double(localX) / (scaleX == 0 ? 1.0 : scaleX)).rounded())
        let imageY = Int((Double(localY) / (scaleY == 0 ? 1.0 : scaleY)).rounded())
        return (
            max(0, min(imageWidth - 1, imageX)),
            max(0, min(imageHeight - 1, imageY))
        )
    }

    func mapImageRectToScreenRect(_ rect: CGRect) -> CGRect {
        let origin = mapImagePointToScreen(x: Int(rect.origin.x.rounded()), y: Int(rect.origin.y.rounded()))
        let width = Int((rect.width * scaleX).rounded())
        let height = Int((rect.height * scaleY).rounded())
        return CGRect(x: origin.x, y: origin.y, width: width, height: height)
    }

    func mapScreenRectToImageRect(_ rect: CGRect) -> CGRect {
        let origin = mapScreenPointToImage(x: Int(rect.origin.x.rounded()), y: Int(rect.origin.y.rounded()))
        let width = Int((rect.width / (scaleX == 0 ? 1.0 : scaleX)).rounded())
        let height = Int((rect.height / (scaleY == 0 ? 1.0 : scaleY)).rounded())
        return CGRect(x: origin.x, y: origin.y, width: width, height: height)
    }
}

enum OpenAIFollowupVisionStrategy {
    case provided(OpenAICapturedScreenshot, String)
    case currentView(String)
    case fullDisplay(String)
}

extension OpenAIComputerUseRunner {
    func defaultGridSpacing(for mode: OpenAIScreenshotMode) -> Int {
        switch mode {
        case .full:
            return 160
        case .crop, .current:
            return 32
        }
    }

    func cursorOverlayOptions(for screenshot: OpenAICapturedScreenshot) -> DesktopScreenshotCursorOverlayOptions? {
        guard let cursor = currentCursorImagePoint(in: screenshot) else { return nil }
        return DesktopScreenshotCursorOverlayOptions(
            center: CGPoint(x: cursor.x, y: cursor.y),
            radius: 20
        )
    }

    func applyVisionState(
        from screenshot: OpenAICapturedScreenshot,
        mode: OpenAIScreenshotMode,
        overlay: OpenAIScreenshotOverlay,
        zoomScale: Double,
        gridSpacing: Int?,
        updateSelectedDisplaySpace: Bool
    ) {
        toolDisplayWidthPx = screenshot.width
        toolDisplayHeightPx = screenshot.height
        coordinateSpaceWidthPx = screenshot.coordinateSpaceWidthPx
        coordinateSpaceHeightPx = screenshot.coordinateSpaceHeightPx
        coordinateSpaceOriginX = screenshot.coordinateSpaceOriginX
        coordinateSpaceOriginY = screenshot.coordinateSpaceOriginY

        if screenshot.width > 0, screenshot.height > 0 {
            coordinateScaleX = Double(screenshot.coordinateSpaceWidthPx) / Double(screenshot.width)
            coordinateScaleY = Double(screenshot.coordinateSpaceHeightPx) / Double(screenshot.height)
        } else {
            coordinateScaleX = 1.0
            coordinateScaleY = 1.0
        }

        if updateSelectedDisplaySpace {
            selectedDisplayCoordinateSpaceWidthPx = screenshot.coordinateSpaceWidthPx
            selectedDisplayCoordinateSpaceHeightPx = screenshot.coordinateSpaceHeightPx
            selectedDisplayCoordinateSpaceOriginX = screenshot.coordinateSpaceOriginX
            selectedDisplayCoordinateSpaceOriginY = screenshot.coordinateSpaceOriginY
        }

        activeVisionState = OpenAIVisionViewState(
            mode: mode,
            overlay: overlay,
            zoomScale: zoomScale,
            gridSpacing: gridSpacing,
            imageWidth: screenshot.width,
            imageHeight: screenshot.height,
            coordinateSpaceWidthPx: screenshot.coordinateSpaceWidthPx,
            coordinateSpaceHeightPx: screenshot.coordinateSpaceHeightPx,
            coordinateSpaceOriginX: screenshot.coordinateSpaceOriginX,
            coordinateSpaceOriginY: screenshot.coordinateSpaceOriginY
        )
    }

    func screenshotByApplyingVisualOverlays(
        to screenshot: OpenAICapturedScreenshot,
        gridSpacing: Int?
    ) throws -> OpenAICapturedScreenshot {
        let overlay = activeVisionState?.overlay ?? .none
        let transform = try DesktopScreenshotTransformService.render(
            screenshot: screenshot,
            cropRect: nil,
            scale: 1.0,
            gridOverlay: overlay == .grid ? DesktopScreenshotGridOverlayOptions(spacing: gridSpacing ?? defaultGridSpacing(for: activeVisionState?.mode ?? .full)) : nil,
            cursorOverlay: cursorOverlayOptions(for: screenshot)
        )
        return OpenAICapturedScreenshot(
            width: transform.width,
            height: transform.height,
            captureWidthPx: transform.width,
            captureHeightPx: transform.height,
            coordinateSpaceWidthPx: screenshot.coordinateSpaceWidthPx,
            coordinateSpaceHeightPx: screenshot.coordinateSpaceHeightPx,
            coordinateSpaceOriginX: screenshot.coordinateSpaceOriginX,
            coordinateSpaceOriginY: screenshot.coordinateSpaceOriginY,
            mediaType: "image/png",
            base64Data: transform.pngData.base64EncodedString(),
            byteCount: transform.pngData.count
        )
    }

    func captureAndApplyFullDisplayScreenshotForLLM(
        source: LLMScreenshotSource,
        overlay: OpenAIScreenshotOverlay,
        gridSpacing: Int?
    ) throws -> OpenAICapturedScreenshot {
        let screenshot = try captureScreenshotForLLM(source: source)
        applyVisionState(
            from: screenshot,
            mode: .full,
            overlay: overlay,
            zoomScale: 1.0,
            gridSpacing: gridSpacing,
            updateSelectedDisplaySpace: true
        )
        return try screenshotByApplyingVisualOverlays(to: screenshot, gridSpacing: gridSpacing)
    }

    func renderCurrentVisionViewForLLM(
        source: LLMScreenshotSource,
        modeOverride: OpenAIScreenshotMode?,
        overlay: OpenAIScreenshotOverlay?,
        gridSpacing: Int?,
        zoomScale: Double?
    ) throws -> OpenAICapturedScreenshot {
        guard let currentState = activeVisionState else {
            return try captureAndApplyFullDisplayScreenshotForLLM(
                source: source,
                overlay: overlay ?? .none,
                gridSpacing: gridSpacing
            )
        }

        let resolvedMode = modeOverride ?? currentState.mode
        if resolvedMode == .full {
            return try captureAndApplyFullDisplayScreenshotForLLM(
                source: source,
                overlay: overlay ?? .none,
                gridSpacing: gridSpacing
            )
        }

        let fullScreenshot = try captureScreenshotForLLM(source: source)
        let cropRect = CGRect(
            x: currentState.coordinateSpaceOriginX - selectedDisplayCoordinateSpaceOriginX,
            y: currentState.coordinateSpaceOriginY - selectedDisplayCoordinateSpaceOriginY,
            width: currentState.coordinateSpaceWidthPx,
            height: currentState.coordinateSpaceHeightPx
        )
        let imageCropRect = CGRect(
            x: cropRect.origin.x,
            y: cropRect.origin.y,
            width: cropRect.width,
            height: cropRect.height
        )
        let resolvedScale = zoomScale ?? currentState.zoomScale
        let resolvedOverlay = overlay ?? currentState.overlay
        let resolvedGridSpacing = gridSpacing ?? currentState.gridSpacing ?? defaultGridSpacing(for: resolvedMode)
        let transform = try DesktopScreenshotTransformService.render(
            screenshot: fullScreenshot,
            cropRect: imageCropRect,
            scale: resolvedScale,
            gridOverlay: resolvedOverlay == .grid ? DesktopScreenshotGridOverlayOptions(spacing: resolvedGridSpacing) : nil,
            cursorOverlay: cursorOverlayOptions(for: fullScreenshot)
        )
        let rendered = OpenAICapturedScreenshot(
            width: transform.width,
            height: transform.height,
            captureWidthPx: transform.width,
            captureHeightPx: transform.height,
            coordinateSpaceWidthPx: currentState.coordinateSpaceWidthPx,
            coordinateSpaceHeightPx: currentState.coordinateSpaceHeightPx,
            coordinateSpaceOriginX: currentState.coordinateSpaceOriginX,
            coordinateSpaceOriginY: currentState.coordinateSpaceOriginY,
            mediaType: "image/png",
            base64Data: transform.pngData.base64EncodedString(),
            byteCount: transform.pngData.count
        )
        applyVisionState(
            from: rendered,
            mode: resolvedMode,
            overlay: resolvedOverlay,
            zoomScale: resolvedScale,
            gridSpacing: resolvedGridSpacing,
            updateSelectedDisplaySpace: false
        )
        return rendered
    }
}
