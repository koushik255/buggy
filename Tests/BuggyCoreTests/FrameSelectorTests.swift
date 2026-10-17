import XCTest
@testable import BuggyCore

final class FrameSelectorTests: XCTestCase {
    func testEmptyInput() {
        let result = FrameSelector.select(samples: [], events: [key(at: 1)], config: .test())
        XCTAssertTrue(result.frames.isEmpty)
        XCTAssertEqual(result.unmatchedEventCount, 1)
    }

    func testStaticClipKeepsOnlyTheOpeningFrame() {
        let result = FrameSelector.select(samples: samples([(0, 0), (1, 0), (2, 0), (3, 0)]), events: [], config: .test())
        XCTAssertEqual(result.frames.map(\.sampleIndex), [0])
        XCTAssertEqual(result.frames.first?.reasons, [.sessionStart])
    }

    func testScreenChangeAndFinalState() {
        let result = FrameSelector.select(
            samples: samples([(0, 0), (1, 40), (2, 40), (3, 40)]),
            events: [],
            config: .test(changeThreshold: 0.05)
        )
        XCTAssertEqual(result.frames.map(\.sampleIndex), [0, 1])
        XCTAssertEqual(result.frames[1].reasons, [.screenChange(delta: delta(0, 40))])
    }

    func testSmallChangeInsideTheIntervalIsDeferredUntilItSettles() {
        let config = ClipConfig.test(changeThreshold: 0.05, majorChangeThreshold: 0.5, minChangeInterval: 1)
        let early = FrameSelector.select(samples: samples([(0, 0), (0.1, 26)]), events: [], config: config)
        XCTAssertEqual(early.frames.map(\.sampleIndex), [0, 1])
        XCTAssertEqual(early.frames[1].reasons, [.sessionEnd])

        let settled = FrameSelector.select(
            samples: samples([(0, 0), (0.1, 26), (1.1, 26)]),
            events: [],
            config: config
        )
        XCTAssertEqual(settled.frames.map(\.sampleIndex), [0, 2])
        XCTAssertTrue(settled.frames[1].reasons.contains(.screenChange(delta: delta(0, 26))))
        XCTAssertTrue(settled.frames[1].reasons.contains(.sessionEnd))
    }

    func testMajorChangeBypassesTheMinimumInterval() {
        let config = ClipConfig.test(changeThreshold: 0.05, majorChangeThreshold: 0.2, minChangeInterval: 1)
        let result = FrameSelector.select(samples: samples([(0, 0), (0.1, 255)]), events: [], config: config)
        XCTAssertEqual(result.frames.map(\.sampleIndex), [0, 1])
        XCTAssertTrue(result.frames[1].reasons.contains(.screenChange(delta: 1)))
    }

    func testClickAndKeyAttachToTheNearestFrame() {
        let result = FrameSelector.select(
            samples: samples([(0, 0), (1, 0), (2, 0)]),
            events: [
                click(at: 0.9, x: 12.5, y: 40),
                key(at: 0.95, name: "Return"),
            ],
            config: .test(eventAssociationWindow: 0.45)
        )
        XCTAssertEqual(result.frames.map(\.sampleIndex), [0, 1])
        XCTAssertEqual(result.frames[1].reasons, [
            .click(x: 12.5, y: 40, button: .left),
            .key(name: "Return"),
        ])
        XCTAssertEqual(result.frames[1].clickMarks, [ClickMark(x: 12.5, y: 40)])
        XCTAssertEqual(result.droppedEventCount, 0)
        XCTAssertEqual(result.unmatchedEventCount, 0)
    }

    func testTwoClicksOnOneFrameBothLeaveMarks() {
        let result = FrameSelector.select(
            samples: samples([(0, 10)]),
            events: [
                click(at: 0.1, x: 1, y: 2, button: .left),
                click(at: 0.2, x: 8, y: 9, button: .right),
            ],
            config: .test()
        )
        XCTAssertEqual(result.frames.count, 1)
        XCTAssertEqual(result.frames[0].clickMarks, [ClickMark(x: 1, y: 2), ClickMark(x: 8, y: 9)])
        XCTAssertEqual(result.frames[0].reasons.first, .sessionStart)
    }

    func testEventOutsideTheWindowIsUnmatched() {
        let result = FrameSelector.select(
            samples: samples([(0, 0), (2, 0)]),
            events: [click(at: 1, x: 1, y: 1)],
            config: .test(eventAssociationWindow: 0.4)
        )
        XCTAssertEqual(result.frames.map(\.sampleIndex), [0])
        XCTAssertEqual(result.unmatchedEventCount, 1)
        XCTAssertFalse(result.frames.contains { $0.reasons.contains { $0.isInput } })
    }

    func testEventOnTheWindowBoundaryStillAttaches() {
        let result = FrameSelector.select(
            samples: samples([(0, 0)]),
            events: [key(at: 0.45, name: "Escape")],
            config: .test(eventAssociationWindow: 0.45)
        )
        XCTAssertEqual(result.unmatchedEventCount, 0)
        XCTAssertTrue(result.frames[0].reasons.contains(.key(name: "Escape")))
    }

    func testCapPrefersClicksOverSmallerScreenChanges() {
        let result = FrameSelector.select(
            samples: samples([(0, 0), (1, 40), (2, 80), (3, 120), (4, 200)]),
            events: [click(at: 2, x: 3, y: 4)],
            config: .test(maxFrames: 3, changeThreshold: 0.05, minChangeInterval: 0)
        )
        XCTAssertEqual(result.frames.map(\.sampleIndex), [0, 2, 4])
        XCTAssertTrue(result.frames[1].reasons.contains(.click(x: 3, y: 4, button: .left)))
        XCTAssertEqual(result.droppedEventCount, 0)
    }

    func testCapKeepsTheLargestRemainingScreenChange() {
        let result = FrameSelector.select(
            samples: samples([(0, 0), (1, 30), (2, 60), (3, 255), (4, 25), (5, 55), (6, 85)]),
            events: [],
            config: .test(maxFrames: 3, changeThreshold: 0.05, majorChangeThreshold: 0.99, minChangeInterval: 0, duplicateThreshold: 0.001)
        )
        XCTAssertEqual(result.frames.map(\.sampleIndex), [0, 4, 6])
    }

    func testCapSpreadsClickFramesAcrossTheClip() {
        let pairs = (0...10).map { (TimeInterval($0), UInt8(0)) }
        let events = (1...10).map { click(at: TimeInterval($0), x: Double($0), y: 1) }
        let result = FrameSelector.select(
            samples: samples(pairs),
            events: events,
            config: .test(maxFrames: 5)
        )
        XCTAssertEqual(result.frames.map(\.sampleIndex), [0, 1, 5, 9, 10])
        XCTAssertEqual(result.droppedEventCount, 6)
    }

    func testSingleFrameBudgetKeepsAClick() {
        let result = FrameSelector.select(
            samples: samples([(0, 0), (1, 80), (2, 160)]),
            events: [click(at: 1, x: 9, y: 9)],
            config: .test(maxFrames: 1, changeThreshold: 0.05, minChangeInterval: 0)
        )
        XCTAssertEqual(result.frames.map(\.sampleIndex), [1])
        XCTAssertEqual(result.droppedEventCount, 0)
    }

    func testReasonsAreOrderedForTheNote() {
        let result = FrameSelector.select(
            samples: samples([(0, 0), (1, 255)]),
            events: [
                key(at: 1, name: "a"),
                click(at: 1, x: 2, y: 3),
            ],
            config: .test(changeThreshold: 0.05, minChangeInterval: 0)
        )
        XCTAssertEqual(result.frames[1].reasons, [
            .click(x: 2, y: 3, button: .left),
            .key(name: "a"),
            .screenChange(delta: 1),
            .sessionEnd,
        ])
    }
}

private func samples(_ pairs: [(TimeInterval, UInt8)]) -> [TimelineSample] {
    pairs.map { TimelineSample(timestamp: $0.0, signature: FrameSignature.solid($0.1, width: 1, height: 1)) }
}

private func delta(_ from: UInt8, _ to: UInt8) -> Double {
    Double(abs(Int(from) - Int(to))) / 255.0
}

private func click(at time: TimeInterval, x: Double, y: Double, button: MouseButton = .left) -> TimelineEvent {
    TimelineEvent(timestamp: time, kind: .click(x: x, y: y, button: button))
}

private func key(at time: TimeInterval, name: String = "a") -> TimelineEvent {
    TimelineEvent(timestamp: time, kind: .key(name: name))
}

private extension ClipConfig {
    static func test(
        maxFrames: Int = 16,
        changeThreshold: Double = 0.06,
        majorChangeThreshold: Double = 0.18,
        minChangeInterval: TimeInterval = 0.35,
        eventAssociationWindow: TimeInterval = 0.45,
        duplicateThreshold: Double = 0.015
    ) -> ClipConfig {
        ClipConfig(
            maxFrames: maxFrames,
            changeThreshold: changeThreshold,
            majorChangeThreshold: majorChangeThreshold,
            duplicateThreshold: duplicateThreshold,
            minChangeInterval: minChangeInterval,
            eventAssociationWindow: eventAssociationWindow,
            sampleFPS: 4,
            maxImageDimension: 1280,
            jpegQuality: 0.72,
            maxDuration: 90,
            signatureGridWidth: 8,
            signatureGridHeight: 8
        )
    }
}
