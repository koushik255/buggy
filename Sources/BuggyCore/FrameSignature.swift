import Foundation

/// Memory layout of a tightly packed image buffer.
public enum PixelLayout: Equatable, Sendable {
    /// One byte per pixel, already luminance.
    case gray8
    /// Four bytes per pixel, red first.
    case rgba8
    /// Four bytes per pixel, blue first. This is what ScreenCaptureKit emits.
    case bgra8
}

/// Downscaled grayscale image used only to decide whether two frames differ.
///
/// Values are 0...255. Comparison is the mean absolute difference divided by
/// 255, so identical frames score 0 and inverted frames score 1.
public struct FrameSignature: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let samples: [UInt8]

    public init(width: Int, height: Int, samples: [UInt8]) {
        precondition(width > 0 && height > 0, "signature dimensions must be positive")
        precondition(samples.count == width * height, "signature sample count must be width * height")
        self.width = width
        self.height = height
        self.samples = samples
    }

    public static func solid(_ value: UInt8, width: Int = 4, height: Int = 4) -> FrameSignature {
        FrameSignature(width: width, height: height, samples: Array(repeating: value, count: width * height))
    }

    /// 0 is identical, 1 is as different as black and white.
    /// Mismatched grids are treated as maximally different.
    public func meanAbsoluteDifference(to other: FrameSignature) -> Double {
        guard width == other.width, height == other.height, !samples.isEmpty else { return 1 }
        var sum = 0
        for index in samples.indices {
            sum += abs(Int(samples[index]) - Int(other.samples[index]))
        }
        return Double(sum) / (Double(samples.count) * 255.0)
    }

    /// Average the source into a fixed grid. Each cell is the mean Rec. 601
    /// luminance of the pixels that fall into it.
    public static func make(
        pixels: [UInt8],
        width: Int,
        height: Int,
        layout: PixelLayout,
        gridWidth: Int,
        gridHeight: Int
    ) -> FrameSignature {
        let gridW = max(1, gridWidth)
        let gridH = max(1, gridHeight)
        let zeros = Array(repeating: UInt8(0), count: gridW * gridH)
        guard width > 0, height > 0 else {
            return FrameSignature(width: gridW, height: gridH, samples: zeros)
        }
        let bytesPerPixel: Int
        switch layout {
        case .gray8:
            bytesPerPixel = 1
        case .rgba8, .bgra8:
            bytesPerPixel = 4
        }
        guard pixels.count >= width * height * bytesPerPixel else {
            return FrameSignature(width: gridW, height: gridH, samples: zeros)
        }

        var samples = zeros
        for cellY in 0..<gridH {
            let y0 = cellY * height / gridH
            let y1 = max(y0 + 1, (cellY + 1) * height / gridH)
            for cellX in 0..<gridW {
                let x0 = cellX * width / gridW
                let x1 = max(x0 + 1, (cellX + 1) * width / gridW)
                var sum = 0
                var count = 0
                for y in y0..<y1 {
                    for x in x0..<x1 {
                        sum += luminance(
                            pixels: pixels,
                            pixelIndex: y * width + x,
                            layout: layout
                        )
                        count += 1
                    }
                }
                samples[cellY * gridW + cellX] = UInt8(sum / max(count, 1))
            }
        }
        return FrameSignature(width: gridW, height: gridH, samples: samples)
    }

    public static func from(raster: RasterImage, gridWidth: Int, gridHeight: Int) -> FrameSignature {
        make(
            pixels: raster.rgba,
            width: raster.width,
            height: raster.height,
            layout: .rgba8,
            gridWidth: gridWidth,
            gridHeight: gridHeight
        )
    }

    private static func luminance(pixels: [UInt8], pixelIndex: Int, layout: PixelLayout) -> Int {
        switch layout {
        case .gray8:
            return Int(pixels[pixelIndex])
        case .rgba8:
            let offset = pixelIndex * 4
            return (299 * Int(pixels[offset]) + 587 * Int(pixels[offset + 1]) + 114 * Int(pixels[offset + 2])) / 1000
        case .bgra8:
            let offset = pixelIndex * 4
            return (299 * Int(pixels[offset + 2]) + 587 * Int(pixels[offset + 1]) + 114 * Int(pixels[offset])) / 1000
        }
    }
}
