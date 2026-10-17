import XCTest
@testable import BuggyCore

final class ClickMarkerTests: XCTestCase {
    func testRingAndCenterAreMarked() {
        let image = RasterImage.solid(width: 21, height: 21, color: RGBAColor(r: 0, g: 0, b: 0))
        let marked = ClickMarker.draw(image, marks: [ClickMark(x: 10.5, y: 10.5)], radius: 4)
        XCTAssertEqual(marked.color(x: 10, y: 10), .markerRed)
        XCTAssertEqual(marked.color(x: 10, y: 6), .markerRed)
        XCTAssertEqual(marked.color(x: 0, y: 0), RGBAColor(r: 0, g: 0, b: 0))
        XCTAssertEqual(marked.width, image.width)
    }

    func testOutsideMarkDoesNotChangeTheImage() {
        let image = RasterImage.solid(width: 8, height: 8, color: RGBAColor(r: 4, g: 5, b: 6))
        let marked = ClickMarker.draw(image, marks: [ClickMark(x: 100, y: -40)], radius: 4)
        XCTAssertEqual(marked, image)
    }

    func testEmptyMarksReturnTheSamePixels() {
        let image = RasterImage.solid(width: 2, height: 2, color: .markerHalo)
        XCTAssertEqual(ClickMarker.draw(image, marks: []), image)
    }

    func testAutomaticRadiusStaysInRange() {
        let small = RasterImage.solid(width: 40, height: 30, color: .markerHalo)
        let large = RasterImage.solid(width: 1280, height: 720, color: .markerHalo)
        XCTAssertGreaterThanOrEqual(ClickMarker.automaticRadius(for: small), 6)
        XCTAssertLessThanOrEqual(ClickMarker.automaticRadius(for: large), 18)
    }
}
