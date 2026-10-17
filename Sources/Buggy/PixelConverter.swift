#if os(macOS)
import BuggyCore
import CoreVideo
import Foundation

enum PixelConverter {
    static func raster(from pixelBuffer: CVPixelBuffer) -> RasterImage? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            return nil
        }
        let lockStatus = CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        guard lockStatus == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 0, height > 0, bytesPerRow >= width * 4 else { return nil }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        rgba.withUnsafeMutableBytes { destination in
            guard let destBase = destination.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let source = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                let row = source.advanced(by: y * bytesPerRow)
                let out = destBase.advanced(by: y * width * 4)
                for x in 0..<width {
                    let pixel = row.advanced(by: x * 4)
                    let slot = out.advanced(by: x * 4)
                    slot[0] = pixel[2]
                    slot[1] = pixel[1]
                    slot[2] = pixel[0]
                    slot[3] = pixel[3]
                }
            }
        }
        return RasterImage(width: width, height: height, rgba: rgba)
    }
}
#endif
