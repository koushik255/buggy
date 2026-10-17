#if os(macOS)
import BuggyCore
import Foundation

enum ExportError: LocalizedError {
    case noFrames
    case unreadable

    var errorDescription: String? {
        switch self {
        case .noFrames:
            return "No frames were captured. If you just granted Screen Recording, quit Buggy and open it again, then clip once more."
        case .unreadable:
            return "The clip note could not be read."
        }
    }
}

struct ClipOutput {
    var directory: URL
    var markdown: String
    var frameCount: Int
}

enum ClipExporter {
    static func export(
        capture: FinishedCapture,
        config: ClipConfig,
        captureLabel: String,
        inputMonitoringEnabled: Bool
    ) throws -> ClipOutput {
        guard let first = capture.frames.first else { throw ExportError.noFrames }
        let config = config.sanitized()
        let samples = capture.frames.map {
            TimelineSample(timestamp: $0.timestamp, signature: $0.signature)
        }
        let events = timelineEvents(from: capture.events, rect: capture.captureRect, width: first.width, height: first.height)
        let selection = FrameSelector.select(samples: samples, events: events, config: config)
        guard !selection.frames.isEmpty else { throw ExportError.noFrames }

        let document = ClipDocument.make(
            startedAt: capture.startedAt,
            duration: capture.duration,
            captureLabel: captureLabel,
            imageWidth: first.width,
            imageHeight: first.height,
            maxFrames: config.maxFrames,
            maxImageDimension: config.maxImageDimension,
            selection: selection,
            inputMonitoringEnabled: inputMonitoringEnabled
        )
        let markdown = document.markdown()
        let directory = try makeDirectory(startedAt: capture.startedAt)
        for record in document.frames {
            let sourceIndex = selection.frames[record.index - 1].sampleIndex
            guard capture.frames.indices.contains(sourceIndex) else { continue }
            let stored = capture.frames[sourceIndex]
            let marks = selection.frames[record.index - 1].clickMarks
            let data = markedJPEG(stored: stored, marks: marks, quality: config.jpegQuality) ?? stored.jpeg
            try data.write(to: directory.appendingPathComponent(record.filename), options: .atomic)
        }
        try markdown.write(to: directory.appendingPathComponent("clip.md"), atomically: true, encoding: .utf8)
        Log.info("wrote \(document.frames.count) frames to \(directory.path)")
        return ClipOutput(directory: directory, markdown: markdown, frameCount: document.frames.count)
    }

    static func clipsDirectory() throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        let folder = documents.appendingPathComponent("Buggy Clips", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func timelineEvents(
        from events: [InputMonitor.RawEvent],
        rect: GlobalRect,
        width: Int,
        height: Int
    ) -> [TimelineEvent] {
        events.compactMap { event in
            switch event.kind {
            case .key(let name):
                return TimelineEvent(timestamp: event.time, kind: .key(name: name))
            case .click(let x, let y, let button):
                guard let pixel = CoordinateMapper.pixelPoint(
                    globalX: x,
                    globalY: y,
                    capture: rect,
                    pixelWidth: width,
                    pixelHeight: height
                ) else {
                    // Still keep a frame for the click, but don't invent a mark off-image.
                    return TimelineEvent(timestamp: event.time, kind: .key(name: "click outside capture"))
                }
                return TimelineEvent(timestamp: event.time, kind: .click(x: pixel.x, y: pixel.y, button: button))
            }
        }
    }

    private static func markedJPEG(stored: StoredFrame, marks: [ClickMark], quality: Double) -> Data? {
        guard !marks.isEmpty, let decoded = JPEGCodec.decode(stored.jpeg) else { return nil }
        let scaleX = stored.width > 0 ? Double(decoded.width) / Double(stored.width) : 1
        let scaleY = stored.height > 0 ? Double(decoded.height) / Double(stored.height) : 1
        let scaled = marks.map { ClickMark(x: $0.x * scaleX, y: $0.y * scaleY) }
        let marked = ClickMarker.draw(decoded, marks: scaled)
        return JPEGCodec.encode(marked, quality: quality)
    }

    private static func makeDirectory(startedAt: Date) throws -> URL {
        let root = try clipsDirectory()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = formatter.string(from: startedAt)
        var url = root.appendingPathComponent(name, isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = root.appendingPathComponent("\(name)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
#endif
