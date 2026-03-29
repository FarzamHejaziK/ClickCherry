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

        let context = runner.visualCoordinateContextValues(for: screenshot).joined(separator: "\n")

        #expect(context.contains("CURRENT_CURSOR"))
        #expect(context.contains("TOP_LEFT: (0, 0)"))
        #expect(context.contains("BOTTOM_RIGHT: (199, 99)"))
    }

    @Test
    func applyVisionStateMapsScreenPointBackIntoImageCoordinates() {
        let runner = OpenAIComputerUseRunner(
            apiKeyStore: VisionStubAPIKeyStore(values: [.openAI: "openai-test-key"]),
            screenshotProvider: { throw OpenAIExecutionPlannerError.screenshotCaptureFailed }
        )

        let screenshot = OpenAICapturedScreenshot(
            width: 200,
            height: 100,
            captureWidthPx: 200,
            captureHeightPx: 100,
            coordinateSpaceWidthPx: 400,
            coordinateSpaceHeightPx: 200,
            coordinateSpaceOriginX: 50,
            coordinateSpaceOriginY: 80,
            mediaType: "image/png",
            base64Data: Data("png".utf8).base64EncodedString(),
            byteCount: 3
        )
        runner.applyVisionState(
            from: screenshot,
            mode: OpenAIScreenshotMode.full,
            overlay: OpenAIScreenshotOverlay.none,
            zoomScale: 1.0,
            gridSpacing: Optional<Int>.none,
            updateSelectedDisplaySpace: true
        )

        let screenPoint = runner.mapToScreenCoordinates(x: 20, y: 30)
        let imagePoint = runner.mapToToolCoordinates(x: screenPoint.x, y: screenPoint.y)

        #expect(imagePoint.x == 20)
        #expect(imagePoint.y == 30)
    }
}
