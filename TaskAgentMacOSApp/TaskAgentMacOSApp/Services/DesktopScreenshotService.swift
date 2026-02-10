import Foundation
import ApplicationServices
import ImageIO

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
    nonisolated static func captureMainDisplayPNG() throws -> DesktopScreenshotCapture {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("taskagent-screenshot-\(UUID().uuidString)")
            .appendingPathExtension("png")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-t", "png", tempURL.path]

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
