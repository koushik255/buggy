import Foundation

public struct ClipFrameRecord: Equatable, Sendable {
    public var index: Int
    public var filename: String
    public var timestamp: TimeInterval
    public var reasons: [FrameReason]

    public init(index: Int, filename: String, timestamp: TimeInterval, reasons: [FrameReason]) {
        self.index = index
        self.filename = filename
        self.timestamp = timestamp
        self.reasons = reasons
    }
}

/// The `clip.md` note that goes in the clip folder, ready to paste next to the images.
public struct ClipDocument: Equatable, Sendable {
    public var startedAt: Date
    public var duration: TimeInterval
    public var captureLabel: String
    public var maxFrames: Int
    public var maxImageDimension: Int
    public var imageWidth: Int?
    public var imageHeight: Int?
    public var frames: [ClipFrameRecord]
    public var droppedEventCount: Int
    public var unmatchedEventCount: Int
    public var inputMonitoringEnabled: Bool

    public init(
        startedAt: Date,
        duration: TimeInterval,
        captureLabel: String,
        maxFrames: Int,
        maxImageDimension: Int,
        imageWidth: Int?,
        imageHeight: Int?,
        frames: [ClipFrameRecord],
        droppedEventCount: Int,
        unmatchedEventCount: Int,
        inputMonitoringEnabled: Bool
    ) {
        self.startedAt = startedAt
        self.duration = duration
        self.captureLabel = captureLabel
        self.maxFrames = maxFrames
        self.maxImageDimension = maxImageDimension
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.frames = frames
        self.droppedEventCount = droppedEventCount
        self.unmatchedEventCount = unmatchedEventCount
        self.inputMonitoringEnabled = inputMonitoringEnabled
    }

    public static func frameFilename(index: Int) -> String {
        String(format: "frame-%02d.jpg", index)
    }

    public static func make(
        startedAt: Date,
        duration: TimeInterval,
        captureLabel: String,
        imageWidth: Int?,
        imageHeight: Int?,
        maxFrames: Int,
        maxImageDimension: Int,
        selection: SelectionResult,
        inputMonitoringEnabled: Bool
    ) -> ClipDocument {
        let frames = selection.frames.enumerated().map { offset, frame in
            let index = offset + 1
            return ClipFrameRecord(
                index: index,
                filename: frameFilename(index: index),
                timestamp: frame.timestamp,
                reasons: frame.reasons
            )
        }
        return ClipDocument(
            startedAt: startedAt,
            duration: duration,
            captureLabel: captureLabel,
            maxFrames: maxFrames,
            maxImageDimension: maxImageDimension,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            frames: frames,
            droppedEventCount: selection.droppedEventCount,
            unmatchedEventCount: selection.unmatchedEventCount,
            inputMonitoringEnabled: inputMonitoringEnabled
        )
    }

    public func markdown(timeZone: TimeZone = .current) -> String {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.timeZone = timeZone
        clock.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var lines = [String]()
        lines.append("# Buggy clip")
        lines.append("")
        lines.append("- Started: \(clock.string(from: startedAt))")
        lines.append("- Duration: \(ClipText.seconds(duration))")
        lines.append("- Capture: \(captureLabel)")
        if let imageWidth, let imageHeight {
            lines.append("- Image size: \(imageWidth)x\(imageHeight) pixels, JPEG, longest side at most \(maxImageDimension)px")
        }
        lines.append("- Frames: \(frames.count) of up to \(maxFrames)")
        lines.append("- Coordinates: pixels in the image, origin at the top-left")
        if inputMonitoringEnabled {
            lines.append("- Input: clicks and keys recorded")
        } else {
            lines.append("- Input: not recorded (Accessibility permission is off). Frames are screen changes only.")
        }
        if droppedEventCount > 0 {
            let noun = droppedEventCount == 1 ? "event" : "events"
            lines.append("- Note: \(droppedEventCount) input \(noun) did not get a frame because the clip is capped at \(maxFrames).")
        }
        if unmatchedEventCount > 0 {
            let noun = unmatchedEventCount == 1 ? "event" : "events"
            lines.append("- Note: \(unmatchedEventCount) input \(noun) had no captured frame close enough to attach.")
        }
        lines.append("")
        lines.append("Attach these images, in order, with this note.")
        lines.append("")
        lines.append("## Frames")
        lines.append("")
        if frames.isEmpty {
            lines.append("(no frames)")
        } else {
            for frame in frames {
                let why = frame.reasons.map(\.summary).joined(separator: "; ")
                lines.append("\(frame.index). `\(frame.filename)` — \(ClipText.seconds(frame.timestamp)) — \(why)")
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
