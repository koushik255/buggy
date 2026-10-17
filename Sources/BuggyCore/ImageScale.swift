import Foundation

public enum ImageScale {
    /// Size that fits inside `maxDimension` on the longest side, preserving aspect ratio.
    /// Never scales up. Returns `(0, 0)` when the input size is not positive.
    public static func fittedSize(width: Int, height: Int, maxDimension: Int) -> (width: Int, height: Int) {
        guard width > 0, height > 0, maxDimension > 0 else { return (0, 0) }
        let longest = max(width, height)
        guard longest > maxDimension else { return (width, height) }
        let scale = Double(maxDimension) / Double(longest)
        return (
            max(1, Int((Double(width) * scale).rounded(.down))),
            max(1, Int((Double(height) * scale).rounded(.down)))
        )
    }

    /// Area-average downsample. Images that already fit are returned unchanged.
    public static func downscale(_ image: RasterImage, maxDimension: Int) -> RasterImage {
        let target = fittedSize(width: image.width, height: image.height, maxDimension: maxDimension)
        guard target.width > 0, target.height > 0 else { return image }
        if target.width == image.width && target.height == image.height {
            return image
        }

        var output = [UInt8](repeating: 0, count: target.width * target.height * 4)
        let sourceWidth = Double(image.width)
        let sourceHeight = Double(image.height)
        for y in 0..<target.height {
            let y0 = Double(y) * sourceHeight / Double(target.height)
            let y1 = Double(y + 1) * sourceHeight / Double(target.height)
            for x in 0..<target.width {
                let x0 = Double(x) * sourceWidth / Double(target.width)
                let x1 = Double(x + 1) * sourceWidth / Double(target.width)
                var accum = (r: 0.0, g: 0.0, b: 0.0, a: 0.0)
                var weight = 0.0
                let ix0 = Int(floor(x0))
                let ix1 = min(image.width - 1, Int(ceil(x1) - 1))
                let iy0 = Int(floor(y0))
                let iy1 = min(image.height - 1, Int(ceil(y1) - 1))
                if ix0 > ix1 || iy0 > iy1 { continue }
                for sy in iy0...iy1 {
                    let rowTop = Double(sy)
                    let rowBottom = Double(sy + 1)
                    let yWeight = min(y1, rowBottom) - max(y0, rowTop)
                    if yWeight <= 0 { continue }
                    for sx in ix0...ix1 {
                        let colLeft = Double(sx)
                        let colRight = Double(sx + 1)
                        let xWeight = min(x1, colRight) - max(x0, colLeft)
                        if xWeight <= 0 { continue }
                        let sampleWeight = xWeight * yWeight
                        let color = image.color(x: sx, y: sy)
                        accum.r += Double(color.r) * sampleWeight
                        accum.g += Double(color.g) * sampleWeight
                        accum.b += Double(color.b) * sampleWeight
                        accum.a += Double(color.a) * sampleWeight
                        weight += sampleWeight
                    }
                }
                let offset = (y * target.width + x) * 4
                output[offset] = channel(accum.r, weight: weight)
                output[offset + 1] = channel(accum.g, weight: weight)
                output[offset + 2] = channel(accum.b, weight: weight)
                output[offset + 3] = channel(accum.a, weight: weight)
            }
        }
        return RasterImage(width: target.width, height: target.height, rgba: output)
    }

    private static func channel(_ accumulated: Double, weight: Double) -> UInt8 {
        guard weight > 0 else { return 0 }
        let value = (accumulated / weight).rounded()
        return UInt8(min(max(value, 0), 255))
    }
}
