import XCTest
@testable import BuggyCore

final class ClipConfigTests: XCTestCase {
    func testSanitizerClampsAndKeepsMajorAboveChange() {
        var config = ClipConfig.default
        config.maxFrames = 0
        config.changeThreshold = 5
        config.majorChangeThreshold = 0.001
        config.duplicateThreshold = -1
        config.minChangeInterval = 99
        config.eventAssociationWindow = 0
        config.sampleFPS = 100
        config.maxImageDimension = 10
        config.jpegQuality = 2
        config.maxDuration = 1
        config.signatureGridWidth = 1
        config.signatureGridHeight = 999
        let clean = config.sanitized()
        XCTAssertEqual(clean.maxFrames, 1)
        XCTAssertEqual(clean.changeThreshold, 0.9)
        XCTAssertGreaterThanOrEqual(clean.majorChangeThreshold, clean.changeThreshold)
        XCTAssertEqual(clean.duplicateThreshold, 0)
        XCTAssertEqual(clean.minChangeInterval, 5)
        XCTAssertEqual(clean.eventAssociationWindow, 0.05)
        XCTAssertEqual(clean.sampleFPS, 15)
        XCTAssertEqual(clean.maxImageDimension, 160)
        XCTAssertEqual(clean.jpegQuality, 0.95)
        XCTAssertEqual(clean.maxDuration, 5)
        XCTAssertEqual(clean.signatureGridWidth, 4)
        XCTAssertEqual(clean.signatureGridHeight, 128)
    }

    func testUpperFrameCap() {
        var config = ClipConfig.default
        config.maxFrames = 10_000
        XCTAssertEqual(config.sanitized().maxFrames, 40)
    }
}
