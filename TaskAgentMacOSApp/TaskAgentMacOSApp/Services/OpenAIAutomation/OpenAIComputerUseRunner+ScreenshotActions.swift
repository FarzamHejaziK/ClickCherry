import CoreGraphics
import Foundation

struct OpenAIScreenshotActionRequest: Equatable {
    var mode: OpenAIScreenshotMode
    var cropOriginX: Int?
    var cropOriginY: Int?
    var cropWidth: Int?
    var cropHeight: Int?
    var scale: Double?
    var overlay: OpenAIScreenshotOverlay
    var gridSpacing: Int?
}

extension OpenAIComputerUseRunner {
    func parseScreenshotActionRequest(from object: [String: OpenAIJSONValue]) -> OpenAIScreenshotActionRequest {
        let mode = OpenAIScreenshotMode(rawValue: object["mode"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "") ?? .full
        let overlay = OpenAIScreenshotOverlay(rawValue: object["overlay"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "") ?? .none
        return OpenAIScreenshotActionRequest(
            mode: mode,
            cropOriginX: object["x"]?.intValue,
            cropOriginY: object["y"]?.intValue,
            cropWidth: object["width"]?.intValue ?? object["w"]?.intValue,
            cropHeight: object["height"]?.intValue ?? object["h"]?.intValue,
            scale: object["scale"]?.doubleValue,
            overlay: overlay,
            gridSpacing: object["grid_spacing"]?.intValue
        )
    }

    func executeScreenshotAction(
        callID: String,
        input: [String: OpenAIJSONValue]
    ) throws -> ToolExecutionResult {
        let request = parseScreenshotActionRequest(from: input)
        let overlay = request.overlay
        let gridSpacing = request.gridSpacing ?? defaultGridSpacing(for: request.mode)

        switch request.mode {
        case .full:
            let screenshot = try captureAndApplyFullDisplayScreenshotForLLM(
                source: .actionScreenshot,
                overlay: overlay,
                gridSpacing: gridSpacing
            )
            return ToolExecutionResult(
                callID: callID,
                output: makeToolOutput(
                    ok: true,
                    message: "Captured full screenshot.",
                    data: [
                        "mode": request.mode.rawValue,
                        "overlay": overlay.rawValue,
                        "image_width": screenshot.width,
                        "image_height": screenshot.height,
                        "coordinate_space_origin_x": screenshot.coordinateSpaceOriginX,
                        "coordinate_space_origin_y": screenshot.coordinateSpaceOriginY,
                        "coordinate_space_width_px": screenshot.coordinateSpaceWidthPx,
                        "coordinate_space_height_px": screenshot.coordinateSpaceHeightPx
                    ]
                ),
                isError: false,
                stepDescription: "Capture full screenshot",
                generatedQuestions: [],
                followupVision: .provided(screenshot, "Full screenshot captured.")
            )

        case .current:
            let screenshot = try renderCurrentVisionViewForLLM(
                source: .actionScreenshot,
                modeOverride: .current,
                overlay: overlay,
                gridSpacing: gridSpacing,
                zoomScale: request.scale
            )
            return ToolExecutionResult(
                callID: callID,
                output: makeToolOutput(
                    ok: true,
                    message: "Captured current view screenshot.",
                    data: [
                        "mode": request.mode.rawValue,
                        "overlay": overlay.rawValue,
                        "image_width": screenshot.width,
                        "image_height": screenshot.height,
                        "coordinate_space_origin_x": screenshot.coordinateSpaceOriginX,
                        "coordinate_space_origin_y": screenshot.coordinateSpaceOriginY,
                        "coordinate_space_width_px": screenshot.coordinateSpaceWidthPx,
                        "coordinate_space_height_px": screenshot.coordinateSpaceHeightPx
                    ]
                ),
                isError: false,
                stepDescription: "Capture current screenshot view",
                generatedQuestions: [],
                followupVision: .provided(screenshot, "Current screenshot view captured.")
            )

        case .crop:
            guard
                let cropOriginX = request.cropOriginX,
                let cropOriginY = request.cropOriginY,
                let cropWidth = request.cropWidth,
                let cropHeight = request.cropHeight
            else {
                return invalidInputResult(callID: callID, action: "screenshot")
            }

            let baseScreenshot = try renderCurrentVisionViewForLLM(
                source: .actionScreenshot,
                modeOverride: .current,
                overlay: .none,
                gridSpacing: nil,
                zoomScale: nil
            )
            let baseState = activeVisionState ?? OpenAIVisionViewState(
                mode: .full,
                overlay: .none,
                zoomScale: 1.0,
                gridSpacing: nil,
                imageWidth: baseScreenshot.width,
                imageHeight: baseScreenshot.height,
                coordinateSpaceWidthPx: baseScreenshot.coordinateSpaceWidthPx,
                coordinateSpaceHeightPx: baseScreenshot.coordinateSpaceHeightPx,
                coordinateSpaceOriginX: baseScreenshot.coordinateSpaceOriginX,
                coordinateSpaceOriginY: baseScreenshot.coordinateSpaceOriginY
            )
            let cropRect = CGRect(x: cropOriginX, y: cropOriginY, width: cropWidth, height: cropHeight).integral
            guard !cropRect.isNull, cropRect.width >= 1, cropRect.height >= 1 else {
                return invalidInputResult(callID: callID, action: "screenshot")
            }

            let resolvedScale = max(1.0, request.scale ?? 2.0)
            let transform = try DesktopScreenshotTransformService.render(
                screenshot: baseScreenshot,
                cropRect: cropRect,
                scale: resolvedScale,
                gridOverlay: overlay == .grid ? DesktopScreenshotGridOverlayOptions(spacing: gridSpacing) : nil,
                cursorOverlay: cursorOverlayOptions(for: baseScreenshot)
            )
            let screenRect = baseState.mapImageRectToScreenRect(cropRect)
            let screenshot = OpenAICapturedScreenshot(
                width: transform.width,
                height: transform.height,
                captureWidthPx: transform.width,
                captureHeightPx: transform.height,
                coordinateSpaceWidthPx: Int(screenRect.width.rounded()),
                coordinateSpaceHeightPx: Int(screenRect.height.rounded()),
                coordinateSpaceOriginX: Int(screenRect.origin.x.rounded()),
                coordinateSpaceOriginY: Int(screenRect.origin.y.rounded()),
                mediaType: "image/png",
                base64Data: transform.pngData.base64EncodedString(),
                byteCount: transform.pngData.count
            )
            applyVisionState(
                from: screenshot,
                mode: .crop,
                overlay: overlay,
                zoomScale: resolvedScale,
                gridSpacing: gridSpacing,
                updateSelectedDisplaySpace: false
            )
            return ToolExecutionResult(
                callID: callID,
                output: makeToolOutput(
                    ok: true,
                    message: "Captured cropped screenshot.",
                    data: [
                        "mode": request.mode.rawValue,
                        "overlay": overlay.rawValue,
                        "image_width": screenshot.width,
                        "image_height": screenshot.height,
                        "coordinate_space_origin_x": screenshot.coordinateSpaceOriginX,
                        "coordinate_space_origin_y": screenshot.coordinateSpaceOriginY,
                        "coordinate_space_width_px": screenshot.coordinateSpaceWidthPx,
                        "coordinate_space_height_px": screenshot.coordinateSpaceHeightPx
                    ]
                ),
                isError: false,
                stepDescription: "Capture crop screenshot (\(cropOriginX), \(cropOriginY), \(cropWidth), \(cropHeight))",
                generatedQuestions: [],
                followupVision: .provided(screenshot, "Cropped screenshot captured.")
            )
        }
    }
}
