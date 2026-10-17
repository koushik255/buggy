#if os(macOS)
import BuggyCore
import CoreMedia
import Foundation
import ScreenCaptureKit

struct StoredFrame {
    var timestamp: TimeInterval
    var jpeg: Data
    var signature: FrameSignature
    var width: Int
    var height: Int
}

struct FinishedCapture {
    var frames: [StoredFrame]
    var events: [InputMonitor.RawEvent]
    var startedAt: Date
    var duration: TimeInterval
    var captureRect: GlobalRect
}

enum CaptureError: LocalizedError {
    case noDisplay
    case windowUnavailable
    case stream(String)

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "No display is available to capture."
        case .windowUnavailable:
            return "That window is no longer available. Open the menu and pick it again."
        case .stream(let message):
            return message
        }
    }
}

/// Samples ScreenCaptureKit frames into memory. Full frames are JPEG-compressed
/// immediately; only the perceptual signature is kept beside the JPEG.
final class CaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    var onAutoStop: (() -> Void)?

    private let queue = DispatchQueue(label: "app.buggy.capture")
    private let lock = NSLock()
    private var stream: SCStream?
    private var frames: [StoredFrame] = []
    private var events: [InputMonitor.RawEvent] = []
    private var config = ClipConfig.default
    private var captureRect = GlobalRect(x: 0, y: 0, width: 1, height: 1)
    private var startUptime: TimeInterval = 0
    private var startedAt = Date()
    private var lastAccepted: TimeInterval = -.infinity
    private var stopped = false
    private var didRequestAutoStop = false
    private var busy = false
    private let maxStoredFrames: Int

    override init() {
        maxStoredFrames = 500
        super.init()
    }

    func elapsed() -> TimeInterval {
        max(0, ProcessInfo.processInfo.systemUptime - startUptime)
    }

    func add(_ event: InputMonitor.RawEvent) {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return }
        events.append(event)
    }

    func start(
        filter: SCContentFilter,
        rect: GlobalRect,
        pixelWidth: Int,
        pixelHeight: Int,
        config: ClipConfig
    ) async throws {
        let config = config.sanitized()
        self.config = config
        captureRect = rect
        startedAt = Date()
        startUptime = ProcessInfo.processInfo.systemUptime
        stopped = false

        let configuration = SCStreamConfiguration()
        configuration.width = max(2, pixelWidth)
        configuration.height = max(2, pixelHeight)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        configuration.queueDepth = 6
        let fps = max(1, Int(config.sampleFPS.rounded()))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.startCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        self.stream = stream
        Log.info("capture started \(pixelWidth)x\(pixelHeight) at \(fps) fps")
    }

    func stop() async -> FinishedCapture {
        lock.lock()
        stopped = true
        lock.unlock()
        if let stream {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                stream.stopCapture { _ in
                    continuation.resume()
                }
            }
        }
        stream = nil
        lock.lock()
        let snapshot = FinishedCapture(
            frames: frames,
            events: events,
            startedAt: startedAt,
            duration: max(0, ProcessInfo.processInfo.systemUptime - startUptime),
            captureRect: captureRect
        )
        lock.unlock()
        Log.info("capture stopped with \(snapshot.frames.count) samples and \(snapshot.events.count) input events")
        return snapshot
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard CMSampleBufferIsValid(sampleBuffer), let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let timestamp = now - startUptime
        let minInterval = 1.0 / max(config.sampleFPS, 1)
        lock.lock()
        let accept = !stopped && !busy && timestamp - lastAccepted >= minInterval && frames.count < maxStoredFrames
        if accept {
            busy = true
            lastAccepted = timestamp
        }
        let shouldStop = !stopped && (timestamp >= config.maxDuration || frames.count >= maxStoredFrames)
        lock.unlock()
        guard accept else {
            if shouldStop { requestAutoStop() }
            return
        }
        defer {
            lock.lock()
            busy = false
            lock.unlock()
        }
        guard var raster = PixelConverter.raster(from: pixelBuffer) else {
            Log.info("skipped a frame that was not BGRA")
            return
        }
        // ScreenCaptureKit on macOS 13 may return the display's native pixels even
        // when a smaller size was requested. Downscale here so the JPEG and the
        // click coordinates share one tested path.
        if max(raster.width, raster.height) > config.maxImageDimension {
            raster = ImageScale.downscale(raster, maxDimension: config.maxImageDimension)
        }
        let signature = FrameSignature.from(
            raster: raster,
            gridWidth: config.signatureGridWidth,
            gridHeight: config.signatureGridHeight
        )
        guard let jpeg = JPEGCodec.encode(raster, quality: config.jpegQuality) else { return }
        let stored = StoredFrame(
            timestamp: max(0, timestamp),
            jpeg: jpeg,
            signature: signature,
            width: raster.width,
            height: raster.height
        )
        lock.lock()
        frames.append(stored)
        let count = frames.count
        lock.unlock()
        if count >= maxStoredFrames || timestamp >= config.maxDuration {
            requestAutoStop()
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.info("stream stopped: \(error.localizedDescription)")
        requestAutoStop()
    }

    private func requestAutoStop() {
        lock.lock()
        let already = didRequestAutoStop || stopped
        didRequestAutoStop = true
        lock.unlock()
        guard !already else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onAutoStop?()
        }
    }
}
#endif
