import XCTest
@testable import BuggyCore

final class ImageScaleTests: XCTestCase {
    func testFittedSizePreservesAspectAndNeverScalesUp() {
        XCTAssertEqual(ImageScale.fittedSize(width: 1920, height: 1080, maxDimension: 1280).width, 1280)
        XCTAssertEqual(ImageScale.fittedSize(width: 1920, height: 1080, maxDimension: 1280).height, 720)
        XCTAssertEqual(ImageScale.fittedSize(width: 100, height: 200, maxDimension: 100).width, 50)
        XCTAssertEqual(ImageScale.fittedSize(width: 100, height: 200, maxDimension: 100).height, 100)
        XCTAssertEqual(ImageScale.fittedSize(width: 50, height: 40, maxDimension: 1280).width, 50)
        XCTAssertEqual(ImageScale.fittedSize(width: 50, height: 40, maxDimension: 1280).height, 40)
        XCTAssertEqual(ImageScale.fittedSize(width: 0, height: 10, maxDimension: 100).width, 0)
    }

    func testDownscaleLeavesSmallImagesAlone() {
        let image = RasterImage.solid(width: 2, height: 2, color: RGBAColor(r: 1, g: 2, b: 3))
        let scaled = ImageScale.downscale(image, maxDimension: 1280)
        XCTAssertEqual(scaled, image)
    }

    func testIntegerBlockAverage() {
        var bytes = [UInt8]()
        for y in 0..<4 {
            for x in 0..<4 {
                let value: UInt8 = x < 2 ? 0 : 255
                _ = y
                bytes.append(contentsOf: [value, value, value, 255])
            }
        }
        let image = RasterImage(width: 4, height: 4, rgba: bytes)
        let scaled = ImageScale.downscale(image, maxDimension: 2)
        XCTAssertEqual(scaled.width, 2)
        XCTAssertEqual(scaled.height, 2)
        XCTAssertEqual(scaled.color(x: 0, y: 0), RGBAColor(r: 0, g: 0, b: 0))
        XCTAssertEqual(scaled.color(x: 1, y: 0), RGBAColor(r: 255, g: 255, b: 255))
        XCTAssertEqual(scaled.color(x: 0, y: 1), RGBAColor(r: 0, g: 0, b: 0))
        XCTAssertEqual(scaled.color(x: 1, y: 1), RGBAColor(r: 255, g: 255, b: 255))
    }

    func testFractionalAreaAverage() {
        let image = RasterImage(
            width: 3,
            height: 1,
            rgba: [
                0, 0, 0, 255,
                0, 0, 0, 255,
                255, 255, 255, 255,
            ]
        )
        let scaled = ImageScale.downscale(image, maxDimension: 2)
        XCTAssertEqual(scaled.width, 2)
        XCTAssertEqual(scaled.height, 1)
        XCTAssertEqual(scaled.color(x: 0, y: 0).r, 0)
        XCTAssertEqual(scaled.color(x: 1, y: 0).r, 170)
        XCTAssertEqual(scaled.color(x: 1, y: 0).a, 255)
    }
}
