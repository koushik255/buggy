import Foundation

/// A click in image pixel space. The origin is the top-left corner of the
/// image, and `(pixelWidth, pixelHeight)` is the bottom-right corner.
/// The center of pixel `(i, j)` is `(Double(i) + 0.5, Double(j) + 0.5)`.
public struct ClickMark: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum ClickMarker {
    /// Draws a white halo, a red ring, and a red center dot for each mark.
    /// Marks completely outside the image are ignored.
    public static func draw(
        _ image: RasterImage,
        marks: [ClickMark],
        color: RGBAColor = .markerRed,
        radius: Int? = nil
    ) -> RasterImage {
        guard !marks.isEmpty else { return image }
        let ring = radius ?? automaticRadius(for: image)
        guard ring > 0 else { return image }
        var bytes = image.rgba
        let dot = max(2, ring / 5)
        for mark in marks {
            guard mark.x >= -Double(ring),
                  mark.y >= -Double(ring),
                  mark.x <= Double(image.width) + Double(ring),
                  mark.y <= Double(image.height) + Double(ring)
            else { continue }
            let minX = max(0, Int(floor(mark.x)) - ring - 3)
            let maxX = min(image.width - 1, Int(ceil(mark.x)) + ring + 3)
            let minY = max(0, Int(floor(mark.y)) - ring - 3)
            let maxY = min(image.height - 1, Int(ceil(mark.y)) + ring + 3)
            if minX > maxX || minY > maxY { continue }
            for y in minY...maxY {
                for x in minX...maxX {
                    let dx = (Double(x) + 0.5) - mark.x
                    let dy = (Double(y) + 0.5) - mark.y
                    let distance = (dx * dx + dy * dy).squareRoot()
                    let paint: RGBAColor?
                    if distance <= Double(dot) {
                        paint = color
                    } else if abs(distance - Double(ring)) <= 1.6 {
                        paint = color
                    } else if abs(distance - Double(ring)) <= 3.1 {
                        paint = .markerHalo
                    } else {
                        paint = nil
                    }
                    if let paint {
                        let offset = (y * image.width + x) * 4
                        bytes[offset] = paint.r
                        bytes[offset + 1] = paint.g
                        bytes[offset + 2] = paint.b
                        bytes[offset + 3] = paint.a
                    }
                }
            }
        }
        return RasterImage(width: image.width, height: image.height, rgba: bytes)
    }

    public static func automaticRadius(for image: RasterImage) -> Int {
        let minSide = min(image.width, image.height)
        return min(18, max(6, minSide / 28))
    }
}
