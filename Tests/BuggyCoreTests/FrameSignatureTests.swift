import XCTest
@testable import BuggyCore

final class FrameSignatureTests: XCTestCase {
    func testIdenticalAndInvertedDifferences() {
        let black = FrameSignature.solid(0, width: 2, height: 2)
        let white = FrameSignature.solid(255, width: 2, height: 2)
        XCTAssertEqual(black.meanAbsoluteDifference(to: black), 0)
        XCTAssertEqual(black.meanAbsoluteDifference(to: white), 1)
        XCTAssertEqual(black.meanAbsoluteDifference(to: FrameSignature.solid(51, width: 2, height: 2)), 0.2, accuracy: 0.000_001)
    }

    func testMismatchedGridsAreMaximallyDifferent() {
        let left = FrameSignature.solid(0, width: 2, height: 2)
        let right = FrameSignature.solid(0, width: 4, height: 2)
        XCTAssertEqual(left.meanAbsoluteDifference(to: right), 1)
    }

    func testGrayGridAveragesBlocks() {
        let signature = FrameSignature.make(
            pixels: [0, 255, 0, 255],
            width: 2,
            height: 2,
            layout: .gray8,
            gridWidth: 1,
            gridHeight: 1
        )
        XCTAssertEqual(signature.samples, [127])

        let identity = FrameSignature.make(
            pixels: [0, 255, 10, 20],
            width: 2,
            height: 2,
            layout: .gray8,
            gridWidth: 2,
            gridHeight: 2
        )
        XCTAssertEqual(identity.samples, [0, 255, 10, 20])
    }

    func testRec601LuminanceForRGBAAndBGRA() {
        let redRGBA = FrameSignature.make(
            pixels: [255, 0, 0, 255],
            width: 1,
            height: 1,
            layout: .rgba8,
            gridWidth: 1,
            gridHeight: 1
        )
        let redBGRA = FrameSignature.make(
            pixels: [0, 0, 255, 255],
            width: 1,
            height: 1,
            layout: .bgra8,
            gridWidth: 1,
            gridHeight: 1
        )
        let blueRGBA = FrameSignature.make(
            pixels: [0, 0, 255, 255],
            width: 1,
            height: 1,
            layout: .rgba8,
            gridWidth: 1,
            gridHeight: 1
        )
        XCTAssertEqual(redRGBA.samples, [76])
        XCTAssertEqual(redBGRA.samples, redRGBA.samples)
        XCTAssertEqual(blueRGBA.samples, [29])
    }

    func testShortBufferReturnsZerosInsteadOfCrashing() {
        let signature = FrameSignature.make(
            pixels: [1, 2],
            width: 4,
            height: 4,
            layout: .rgba8,
            gridWidth: 2,
            gridHeight: 2
        )
        XCTAssertEqual(signature.samples, [0, 0, 0, 0])
    }

    func testRasterSignatureUsesRGBA() {
        let image = RasterImage.solid(width: 1, height: 1, color: RGBAColor(r: 255, g: 0, b: 0))
        let signature = FrameSignature.from(raster: image, gridWidth: 1, gridHeight: 1)
        XCTAssertEqual(signature.samples, [76])
    }
}
