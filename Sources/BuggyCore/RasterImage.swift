import Foundation

public struct RGBAColor: Equatable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// System red, close to the macOS destructive red.
    public static let markerRed = RGBAColor(r: 255, g: 59, b: 48)
    public static let markerHalo = RGBAColor(r: 255, g: 255, b: 255)
}

/// Top-down RGBA image. Row 0 is the top of the image. Alpha is straight.
public struct RasterImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let rgba: [UInt8]

    public init(width: Int, height: Int, rgba: [UInt8]) {
        precondition(width > 0 && height > 0, "image dimensions must be positive")
        precondition(rgba.count == width * height * 4, "rgba count must be width * height * 4")
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    public static func solid(width: Int, height: Int, color: RGBAColor) -> RasterImage {
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height * 4)
        for _ in 0..<(width * height) {
            bytes.append(color.r)
            bytes.append(color.g)
            bytes.append(color.b)
            bytes.append(color.a)
        }
        return RasterImage(width: width, height: height, rgba: bytes)
    }

    public func color(x: Int, y: Int) -> RGBAColor {
        let offset = (y * width + x) * 4
        return RGBAColor(r: rgba[offset], g: rgba[offset + 1], b: rgba[offset + 2], a: rgba[offset + 3])
    }
}
