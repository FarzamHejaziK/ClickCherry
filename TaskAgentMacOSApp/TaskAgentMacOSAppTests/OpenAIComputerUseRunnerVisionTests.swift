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
}
