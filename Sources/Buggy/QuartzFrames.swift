#if os(macOS)
import BuggyCore
import CoreGraphics
import Foundation

/// Capture rectangles in Quartz global space (top-left origin, y down).
enum QuartzFrames {
    static func displayRect(displayID: CGDirectDisplayID) -> GlobalRect {
        let bounds = CGDisplayBounds(displayID)
        return GlobalRect(
            x: bounds.origin.x,
            y: bounds.origin.y,
            width: bounds.size.width,
            height: bounds.size.height
        )
    }

    static func windowRect(windowID: CGWindowID, fallback: CGRect) -> GlobalRect {
        if let bounds = windowBounds(windowID: windowID), bounds.width > 1, bounds.height > 1 {
            return GlobalRect(x: bounds.origin.x, y: bounds.origin.y, width: bounds.width, height: bounds.height)
        }
        return GlobalRect(
            x: fallback.origin.x,
            y: fallback.origin.y,
            width: fallback.size.width,
            height: fallback.size.height
        )
    }

    private static func windowBounds(windowID: CGWindowID) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]],
              let info = list.first,
              let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary)
        else { return nil }
        return rect
    }
}
#endif
