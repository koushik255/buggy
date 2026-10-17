import XCTest
@testable import BuggyCore

final class ClipDocumentTests: XCTestCase {
    func testMarkdownListsFramesTriggersAndNotes() {
        let selection = FrameSelector.select(
            samples: [
                TimelineSample(timestamp: 0, signature: .solid(0, width: 1, height: 1)),
                TimelineSample(timestamp: 1.2, signature: .solid(0, width: 1, height: 1)),
                TimelineSample(timestamp: 4.2, signature: .solid(255, width: 1, height: 1)),
            ],
            events: [
                TimelineEvent(timestamp: 1.25, kind: .click(x: 10, y: 20, button: .left)),
                TimelineEvent(timestamp: 9, kind: .key(name: "Escape")),
            ],
            config: ClipConfig(
                maxFrames: 16,
                changeThreshold: 0.05,
                majorChangeThreshold: 0.2,
                duplicateThreshold: 0.015,
                minChangeInterval: 0,
                eventAssociationWindow: 0.45,
                sampleFPS: 4,
                maxImageDimension: 1280,
                jpegQuality: 0.72,
                maxDuration: 90,
                signatureGridWidth: 4,
                signatureGridHeight: 4
            )
        )
        let document = ClipDocument.make(
            startedAt: Date(timeIntervalSince1970: 0),
            duration: 4.2,
            captureLabel: "Built-in Display",
            imageWidth: 1280,
            imageHeight: 720,
            maxFrames: 16,
            maxImageDimension: 1280,
            selection: selection,
            inputMonitoringEnabled: true
        )
        let markdown = document.markdown(timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(
            markdown,
            """
            # Buggy clip

            - Started: 1970-01-01 00:00:00
            - Duration: 4.20s
            - Capture: Built-in Display
            - Image size: 1280x720 pixels, JPEG, longest side at most 1280px
            - Frames: 3 of up to 16
            - Coordinates: pixels in the image, origin at the top-left
            - Input: clicks and keys recorded
            - Note: 1 input event had no captured frame close enough to attach.

            Attach these images, in order, with this note.

            ## Frames

            1. `frame-01.jpg` — 0.00s — session start
            2. `frame-02.jpg` — 1.20s — click left at (10, 20)
            3. `frame-03.jpg` — 4.20s — screen change (delta 1.00); session end

            """
        )
    }

    func testMarkdownExplainsADisabledEventTapAndTheFrameCap() {
        let document = ClipDocument(
            startedAt: Date(timeIntervalSince1970: 0),
            duration: 1,
            captureLabel: "Safari — Inbox",
            maxFrames: 2,
            maxImageDimension: 1280,
            imageWidth: nil,
            imageHeight: nil,
            frames: [
                ClipFrameRecord(index: 1, filename: "frame-01.jpg", timestamp: 0, reasons: [.sessionStart]),
            ],
            droppedEventCount: 2,
            unmatchedEventCount: 0,
            inputMonitoringEnabled: false
        )
        let markdown = document.markdown(timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertTrue(markdown.contains("Accessibility permission is off"))
        XCTAssertTrue(markdown.contains("2 input events did not get a frame because the clip is capped at 2."))
        XCTAssertTrue(markdown.contains("Safari — Inbox"))
        XCTAssertFalse(markdown.contains("Image size:"))
    }
}
