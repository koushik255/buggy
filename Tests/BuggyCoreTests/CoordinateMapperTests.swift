import XCTest
@testable import BuggyCore

final class CoordinateMapperTests: XCTestCase {
    func testMapsTopLeftPointSpaceIntoPixels() {
        let capture = GlobalRect(x: 0, y: 0, width: 100, height: 50)
        let point = CoordinateMapper.pixelPoint(
            globalX: 25,
            globalY: 10,
            capture: capture,
            pixelWidth: 200,
            pixelHeight: 100
        )
        XCTAssertEqual(point?.x ?? -1, 50, accuracy: 0.000_001)
        XCTAssertEqual(point?.y ?? -1, 20, accuracy: 0.000_001)
    }

    func testTopLeftOfTheRectIsTheTopLeftPixel() {
        let capture = GlobalRect(x: 10, y: 30, width: 80, height: 40)
        let point = CoordinateMapper.pixelPoint(
            globalX: 10,
            globalY: 30,
            capture: capture,
            pixelWidth: 800,
            pixelHeight: 400
        )
        XCTAssertEqual(point?.x ?? -1, 0, accuracy: 0.000_001)
        XCTAssertEqual(point?.y ?? -1, 0, accuracy: 0.000_001)
    }

    func testSecondaryDisplayOrigin() {
        let capture = GlobalRect(x: 1920, y: 100, width: 100, height: 100)
        let point = CoordinateMapper.pixelPoint(
            globalX: 1960,
            globalY: 150,
            capture: capture,
            pixelWidth: 100,
            pixelHeight: 100
        )
        XCTAssertEqual(point?.x ?? -1, 40, accuracy: 0.000_001)
        XCTAssertEqual(point?.y ?? -1, 50, accuracy: 0.000_001)
    }

    func testFarEdgeIsIncludedAndOutsideIsNil() {
        let capture = GlobalRect(x: 0, y: 0, width: 100, height: 50)
        let edge = CoordinateMapper.pixelPoint(
            globalX: 100,
            globalY: 50,
            capture: capture,
            pixelWidth: 200,
            pixelHeight: 100
        )
        XCTAssertEqual(edge?.x ?? -1, 200, accuracy: 0.000_001)
        XCTAssertEqual(edge?.y ?? -1, 100, accuracy: 0.000_001)
        XCTAssertNil(CoordinateMapper.pixelPoint(globalX: -0.1, globalY: 10, capture: capture, pixelWidth: 10, pixelHeight: 10))
        XCTAssertNil(CoordinateMapper.pixelPoint(globalX: 10, globalY: 10, capture: capture, pixelWidth: 0, pixelHeight: 10))
        XCTAssertNil(CoordinateMapper.pixelPoint(
            globalX: 1,
            globalY: 1,
            capture: GlobalRect(x: 0, y: 0, width: 0, height: 10),
            pixelWidth: 10,
            pixelHeight: 10
        ))
    }
}
