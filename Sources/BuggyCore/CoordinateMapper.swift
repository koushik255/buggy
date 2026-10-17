import Foundation

/// Rectangle in a top-left, y-down point space.
///
/// On macOS this is Quartz global display space: the origin is the top-left
/// of the main display, and y increases downward. `CGEvent.location`,
/// `CGDisplayBounds`, and `kCGWindowBounds` all use that space. Captured
/// pixel buffers use the same axis direction, so mapping does not flip y.
public struct GlobalRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum CoordinateMapper {
    /// Converts a point in the same space as `capture` into pixel coordinates
    /// of the captured image. Returns nil when the point is outside the rect.
    ///
    /// The result uses the pixel-buffer convention: `(0, 0)` is the top-left
    /// corner and `(pixelWidth, pixelHeight)` is the bottom-right corner.
    public static func pixelPoint(
        globalX: Double,
        globalY: Double,
        capture: GlobalRect,
        pixelWidth: Int,
        pixelHeight: Int
    ) -> (x: Double, y: Double)? {
        guard capture.width > 0, capture.height > 0, pixelWidth > 0, pixelHeight > 0 else {
            return nil
        }
        let localX = globalX - capture.x
        let localY = globalY - capture.y
        let slop = 0.000_001
        guard localX >= -slop, localY >= -slop,
              localX <= capture.width + slop,
              localY <= capture.height + slop
        else { return nil }
        let clampedX = min(max(localX, 0), capture.width)
        let clampedY = min(max(localY, 0), capture.height)
        return (
            clampedX / capture.width * Double(pixelWidth),
            clampedY / capture.height * Double(pixelHeight)
        )
    }
}
