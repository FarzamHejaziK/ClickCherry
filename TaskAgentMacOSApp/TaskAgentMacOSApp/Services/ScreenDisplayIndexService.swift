import AppKit
import CoreGraphics

/// Central mapping between:
/// - `screencapture -D <displayIndex>` (1 = main, 2 = secondary, ...)
/// - `NSScreen` instances (AppKit ordering)
/// - `CGDirectDisplayID` (for thumbnails / display-ID based APIs)
///
/// Important: We intentionally derive ordering from `NSScreen` (main first) because it is the
/// user-facing display ordering in AppKit, and empirically aligns with `screencapture -D`.
enum ScreenDisplayIndexService {
    static func orderedScreensMainFirst() -> [NSScreen] {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return [] }

        if let main = NSScreen.main,
           let mainIndex = screens.firstIndex(where: { $0 == main }) {
            var ordered = screens
            ordered.remove(at: mainIndex)
            ordered.insert(main, at: 0)
            return ordered
        }

        return screens
    }

    /// 1-based display index used by `screencapture -D`.
    static func screenForScreencaptureDisplayIndex(_ displayIndex: Int) -> NSScreen? {
        let ordered = orderedScreensMainFirst()
        guard displayIndex >= 1, displayIndex <= ordered.count else { return nil }
        return ordered[displayIndex - 1]
    }

    static func cgDisplayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let raw = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(raw.uint32Value)
    }
}

