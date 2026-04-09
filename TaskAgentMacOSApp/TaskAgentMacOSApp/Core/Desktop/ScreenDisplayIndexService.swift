import AppKit
import CoreGraphics

/// Central mapping between:
/// - `screencapture -D <displayIndex>` (1 = main, 2 = secondary, ...)
/// - `NSScreen` instances (AppKit ordering)
/// - `CGDirectDisplayID` (for thumbnails / display-ID based APIs)
///
/// Important: Do not use `NSScreen.main` here. `NSScreen.main` tracks the key window's display,
/// not the system primary display used by `screencapture -D 1`.
enum ScreenDisplayIndexService {
    static func orderedScreensMainFirst() -> [NSScreen] {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return [] }

        let screenMappings = screens.compactMap { screen -> (displayID: CGDirectDisplayID, screen: NSScreen)? in
            guard let displayID = cgDisplayID(for: screen) else {
                return nil
            }
            return (displayID, screen)
        }
        guard screenMappings.count == screens.count else { return screens }

        let appKitOrder = screenMappings.map(\.displayID)
        let orderedIDs = orderedDisplayIDsForScreencapture(mainDisplayID: CGMainDisplayID(), appKitOrder: appKitOrder)
        guard orderedIDs != appKitOrder else { return screens }

        let orderedScreens = orderedIDs.compactMap { displayID in
            screenMappings.first(where: { $0.displayID == displayID })?.screen
        }
        guard orderedScreens.count == screens.count else { return screens }
        return orderedScreens
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

    /// `CGDirectDisplayID` for a 1-based `screencapture -D` display index.
    static func cgDisplayIDForScreencaptureDisplayIndex(_ displayIndex: Int) -> CGDirectDisplayID? {
        guard let screen = screenForScreencaptureDisplayIndex(displayIndex) else {
            return nil
        }
        return cgDisplayID(for: screen)
    }

    /// Best-effort reverse lookup of a 1-based `screencapture -D` display index for a display id.
    static func screencaptureDisplayIndex(for displayID: CGDirectDisplayID) -> Int? {
        let ordered = orderedScreensMainFirst()
        for (idx, screen) in ordered.enumerated() {
            if let id = cgDisplayID(for: screen), id == displayID {
                return idx + 1
            }
        }
        return nil
    }

    /// Produces `screencapture -D` index order from AppKit screen order.
    /// `screencapture -D 1` maps to the system primary display (`CGMainDisplayID()`).
    static func orderedDisplayIDsForScreencapture(
        mainDisplayID: CGDirectDisplayID,
        appKitOrder: [CGDirectDisplayID]
    ) -> [CGDirectDisplayID] {
        guard let mainIndex = appKitOrder.firstIndex(of: mainDisplayID), mainIndex > 0 else {
            return appKitOrder
        }

        var ordered = appKitOrder
        let primary = ordered.remove(at: mainIndex)
        ordered.insert(primary, at: 0)
        return ordered
    }
}
