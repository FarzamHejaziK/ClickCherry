import AppKit
import Foundation
import Testing
@testable import TaskAgentMacOSApp

private final class VisionStubAPIKeyStore: APIKeyStore {
    private let values: [ProviderIdentifier: String]

    init(values: [ProviderIdentifier: String]) {
        self.values = values
    }

    func hasKey(for provider: ProviderIdentifier) -> Bool {
        guard let value = values[provider] else { return false }
        return !value.isEmpty
    }

    func readKey(for provider: ProviderIdentifier) throws -> String? {
        values[provider]
    }

    func setKey(_ key: String?, for provider: ProviderIdentifier) throws {}
}

struct OpenAIComputerUseRunnerVisionTests {
    @Test
    func visualCoordinateContextIncludesCursorAndCorners() {
        let runner = OpenAIComputerUseRunner(
            apiKeyStore: VisionStubAPIKeyStore(values: [.openAI: "openai-test-key"]),
            screenshotProvider: {
                OpenAICapturedScreenshot(
                    width: 200,
                    height: 100,
                    captureWidthPx: 200,
                    captureHeightPx: 100,
                    coordinateSpaceWidthPx: 400,
                    coordinateSpaceHeightPx: 200,
                    coordinateSpaceOriginX: 10,
                    coordinateSpaceOriginY: 20,
                    mediaType: "image/png",
                    base64Data: Data("png".utf8).base64EncodedString(),
                    byteCount: 3
                )
            },
            cursorPositionProvider: { (110, 70) }
        )

        let screenshot = OpenAICapturedScreenshot(
            width: 200,
            height: 100,
            captureWidthPx: 200,
            captureHeightPx: 100,
            coordinateSpaceWidthPx: 400,
            coordinateSpaceHeightPx: 200,
            coordinateSpaceOriginX: 10,
            coordinateSpaceOriginY: 20,
            mediaType: "image/png",
            base64Data: Data("png".utf8).base64EncodedString(),
            byteCount: 3
        )

        runner.selectedDisplayCoordinateSpaceOriginX = 10
        runner.selectedDisplayCoordinateSpaceOriginY = 20
        runner.selectedDisplayCoordinateSpaceWidthPx = 400
        runner.selectedDisplayCoordinateSpaceHeightPx = 200

        let context = runner.visualCoordinateContextValues(for: screenshot).joined(separator: "\n")

        #expect(context.contains("CURRENT_CURSOR: (100, 50)"))
        #expect(context.contains("TOP_LEFT: (0, 0)"))
        #expect(context.contains("BOTTOM_RIGHT: (399, 199)"))
        #expect(context.contains("selected display coordinate system"))
    }

    @Test
    func visualCoordinateContextReportsCursorOutsideCurrentImageUsingDisplayCoordinates() {
        let runner = OpenAIComputerUseRunner(
            apiKeyStore: VisionStubAPIKeyStore(values: [.openAI: "openai-test-key"]),
            screenshotProvider: { throw OpenAIExecutionPlannerError.screenshotCaptureFailed },
            cursorPositionProvider: { (110, 70) }
        )

        let screenshot = OpenAICapturedScreenshot(
            width: 200,
            height: 100,
            captureWidthPx: 200,
            captureHeightPx: 100,
            coordinateSpaceWidthPx: 80,
            coordinateSpaceHeightPx: 40,
            coordinateSpaceOriginX: 210,
            coordinateSpaceOriginY: 120,
            mediaType: "image/png",
            base64Data: Data("png".utf8).base64EncodedString(),
            byteCount: 3
        )

        runner.selectedDisplayCoordinateSpaceOriginX = 10
        runner.selectedDisplayCoordinateSpaceOriginY = 20
        runner.selectedDisplayCoordinateSpaceWidthPx = 400
        runner.selectedDisplayCoordinateSpaceHeightPx = 200

        let context = runner.visualCoordinateContextValues(for: screenshot).joined(separator: "\n")

        #expect(context.contains("CURRENT_CURSOR: outside current image; actual=(100, 50)"))
        #expect(context.contains("TOP_LEFT: (200, 100)"))
        #expect(context.contains("BOTTOM_RIGHT: (279, 139)"))
    }

    @Test
    func screenshotToolOutputDataIncludesCurrentCursorMetadata() throws {
        let pngData = try Self.makeValidPNGData(width: 16, height: 16)
        let runner = OpenAIComputerUseRunner(
            apiKeyStore: VisionStubAPIKeyStore(values: [.openAI: "openai-test-key"]),
            screenshotProvider: { throw OpenAIExecutionPlannerError.screenshotCaptureFailed },
            cursorPositionProvider: { (230, 150) }
        )

        runner.selectedDisplayCoordinateSpaceOriginX = 10
        runner.selectedDisplayCoordinateSpaceOriginY = 20
        runner.selectedDisplayCoordinateSpaceWidthPx = 400
        runner.selectedDisplayCoordinateSpaceHeightPx = 200

        let screenshot = OpenAICapturedScreenshot(
            width: 32,
            height: 16,
            captureWidthPx: 32,
            captureHeightPx: 16,
            coordinateSpaceWidthPx: 160,
            coordinateSpaceHeightPx: 80,
            coordinateSpaceOriginX: 110,
            coordinateSpaceOriginY: 100,
            mediaType: "image/png",
            base64Data: pngData.base64EncodedString(),
            byteCount: pngData.count
        )

        let data = runner.screenshotToolOutputData(for: screenshot, mode: .crop, overlay: .grid)

        #expect(data["coordinate_system"] as? String == "selected_display")
        #expect(data["coordinate_space_origin_x"] as? Int == 100)
        #expect(data["coordinate_space_origin_y"] as? Int == 80)
        #expect(data["current_cursor_x"] as? Int == 220)
        #expect(data["current_cursor_y"] as? Int == 130)
        #expect(data["current_cursor_visible_in_image"] as? Bool == true)
        #expect(data["current_cursor_status"] as? String == "visible")
    }

    @Test
    func screenshotToolOutputDataMarksCursorOutsideCurrentImage() {
        let runner = OpenAIComputerUseRunner(
            apiKeyStore: VisionStubAPIKeyStore(values: [.openAI: "openai-test-key"]),
            screenshotProvider: { throw OpenAIExecutionPlannerError.screenshotCaptureFailed },
            cursorPositionProvider: { (110, 70) }
        )

        runner.selectedDisplayCoordinateSpaceOriginX = 10
        runner.selectedDisplayCoordinateSpaceOriginY = 20
        runner.selectedDisplayCoordinateSpaceWidthPx = 400
        runner.selectedDisplayCoordinateSpaceHeightPx = 200

        let screenshot = OpenAICapturedScreenshot(
            width: 20,
            height: 10,
            captureWidthPx: 20,
            captureHeightPx: 10,
            coordinateSpaceWidthPx: 40,
            coordinateSpaceHeightPx: 20,
            coordinateSpaceOriginX: 210,
            coordinateSpaceOriginY: 120,
            mediaType: "image/png",
            base64Data: Data("png".utf8).base64EncodedString(),
            byteCount: 3
        )

        let data = runner.screenshotToolOutputData(for: screenshot, mode: .current, overlay: .none)

        #expect(data["current_cursor_x"] as? Int == 100)
        #expect(data["current_cursor_y"] as? Int == 50)
        #expect(data["current_cursor_visible_in_image"] as? Bool == false)
        #expect(data["current_cursor_status"] as? String == "outside_current_image")
    }

    @Test
    func selectedDisplayCoordinatesMapDirectlyToScreenCoordinates() {
        let runner = OpenAIComputerUseRunner(
            apiKeyStore: VisionStubAPIKeyStore(values: [.openAI: "openai-test-key"]),
            screenshotProvider: { throw OpenAIExecutionPlannerError.screenshotCaptureFailed }
        )

        runner.selectedDisplayCoordinateSpaceOriginX = 50
        runner.selectedDisplayCoordinateSpaceOriginY = 80
        runner.selectedDisplayCoordinateSpaceWidthPx = 400
        runner.selectedDisplayCoordinateSpaceHeightPx = 200

        let screenPoint = runner.mapToScreenCoordinates(x: 20, y: 30)
        let imagePoint = runner.mapToToolCoordinates(x: screenPoint.x, y: screenPoint.y)

        #expect(screenPoint.x == 70)
        #expect(screenPoint.y == 110)
        #expect(imagePoint.x == 20)
        #expect(imagePoint.y == 30)
    }

    private static func makeValidPNGData(width: Int, height: Int) throws -> Data {
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
            throw NSError(domain: "OpenAIComputerUseRunnerVisionTests", code: 1)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(calibratedWhite: 0.95, alpha: 1.0).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "OpenAIComputerUseRunnerVisionTests", code: 2)
        }
        return pngData
    }
}
