import Foundation
import ApplicationServices
@preconcurrency import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers

enum DesktopScreenshotServiceError: Error, Equatable {
    case captureFailed
    case decodeFailed
}

struct DesktopScreenshotCapture: Equatable {
    var pngData: Data
    var width: Int
    var height: Int
}

struct DesktopScreenshotService {
    nonisolated private final class Box<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) {
            self.value = value
        }
    }

    nonisolated static func captureMainDisplayPNG(excludingWindowNumber: Int? = nil) throws -> DesktopScreenshotCapture {
        // Quartz window-list capture APIs are deprecated on macOS 14 and removed on macOS 15+.
        // Use ScreenCaptureKit so we can (optionally) exclude our “Agent is running” HUD window
        // from LLM screenshots without hiding it on the user's screen.
        do {
            return try captureMainDisplayPNGViaScreenCaptureKit(excludingWindowNumber: excludingWindowNumber)
        } catch {
            // Fallback: `screencapture` cannot exclude specific windows.
            // If an exclusion was requested, fail closed so the model never sees the HUD overlay.
            if excludingWindowNumber != nil {
                throw error
            }
            // No exclusion required: use `screencapture` as a pragmatic escape hatch.
            return try captureMainDisplayPNGViaScreencapture()
        }
    }

    nonisolated private static func captureMainDisplayPNGViaScreenCaptureKit(excludingWindowNumber: Int?) throws -> DesktopScreenshotCapture {
        let mainDisplayID = CGMainDisplayID()

        let content = try loadShareableContent(onScreenOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == mainDisplayID }) else {
            throw DesktopScreenshotServiceError.captureFailed
        }

        // Best-effort: exclude the overlay window if we can find it in the shareable window list.
        var excludedWindows: [SCWindow] = []
        if let excludingWindowNumber, excludingWindowNumber > 0 {
            let targetID = CGWindowID(excludingWindowNumber)
            if let match = content.windows.first(where: { $0.windowID == targetID }) {
                excludedWindows = [match]
            }
        }

        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)

        let config = SCStreamConfiguration()
        // Capture at “nominal” resolution (point-space) so our LLM tool coordinate space matches
        // the CGEvent injection coordinate space (and keeps payload sizes smaller on Retina).
        config.captureResolution = .nominal
        config.width = size_t(max(1, display.width))
        config.height = size_t(max(1, display.height))
        // Include the cursor so hover/mouse-position tasks can be grounded visually.
        config.showsCursor = true

        let cgImage = try captureImage(filter: filter, config: config)
        let pngData = try encodePNG(cgImage: cgImage)

        return DesktopScreenshotCapture(
            pngData: pngData,
            width: cgImage.width,
            height: cgImage.height
        )
    }

    nonisolated private static func loadShareableContent(onScreenOnly: Bool) throws -> SCShareableContent {
        let semaphore = DispatchSemaphore(value: 0)
        let box = Box<Result<SCShareableContent, Error>>(.failure(DesktopScreenshotServiceError.captureFailed))

        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: onScreenOnly) { content, error in
            if let content {
                box.value = .success(content)
            } else if let error {
                box.value = .failure(error)
            } else {
                box.value = .failure(DesktopScreenshotServiceError.captureFailed)
            }
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 10) == .timedOut {
            throw DesktopScreenshotServiceError.captureFailed
        }
        return try box.value.get()
    }

    nonisolated private static func captureImage(filter: SCContentFilter, config: SCStreamConfiguration) throws -> CGImage {
        let semaphore = DispatchSemaphore(value: 0)
        let box = Box<Result<CGImage, Error>>(.failure(DesktopScreenshotServiceError.captureFailed))

        SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { cgImage, error in
            if let cgImage {
                box.value = .success(cgImage)
            } else if let error {
                box.value = .failure(error)
            } else {
                box.value = .failure(DesktopScreenshotServiceError.captureFailed)
            }
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 10) == .timedOut {
            throw DesktopScreenshotServiceError.captureFailed
        }
        return try box.value.get()
    }

    nonisolated private static func encodePNG(cgImage: CGImage) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw DesktopScreenshotServiceError.captureFailed
        }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw DesktopScreenshotServiceError.captureFailed
        }
        return output as Data
    }

    nonisolated private static func captureMainDisplayPNGViaScreencapture() throws -> DesktopScreenshotCapture {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("taskagent-screenshot-\(UUID().uuidString)")
            .appendingPathExtension("png")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-C", "-t", "png", tempURL.path]

        do {
            try process.run()
        } catch {
            throw DesktopScreenshotServiceError.captureFailed
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DesktopScreenshotServiceError.captureFailed
        }

        let pngData: Data
        do {
            pngData = try Data(contentsOf: tempURL)
        } catch {
            throw DesktopScreenshotServiceError.captureFailed
        }

        guard
            let imageSource = CGImageSourceCreateWithData(pngData as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            throw DesktopScreenshotServiceError.decodeFailed
        }

        return DesktopScreenshotCapture(
            pngData: pngData,
            width: cgImage.width,
            height: cgImage.height
        )
    }
}
