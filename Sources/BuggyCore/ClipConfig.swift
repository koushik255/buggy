import Foundation

/// Knobs for sampling, frame selection, and image export.
///
/// The macOS app starts from ``default`` and may override fields from the
/// menu (max frames) or UserDefaults. ``sanitized()`` clamps every field
/// into the range the selector understands.
public struct ClipConfig: Equatable, Sendable {
    /// Maximum frames written into one clip, including the opening frame.
    public var maxFrames: Int
    /// Mean absolute luminance difference (0...1) that counts as a change
    /// once `minChangeInterval` has elapsed.
    public var changeThreshold: Double
    /// A difference this large is kept immediately, even inside the minimum interval.
    public var majorChangeThreshold: Double
    /// Screen-change frames closer than this to the previous kept frame are dropped.
    /// Click and key frames are kept anyway.
    public var duplicateThreshold: Double
    /// Minimum time between ordinary screen-change frames.
    public var minChangeInterval: TimeInterval
    /// How far a click or key can be from a captured frame and still attach to it.
    public var eventAssociationWindow: TimeInterval
    /// How many frames per second to keep in memory while recording.
    public var sampleFPS: Double
    /// Longest side of an exported JPEG, in pixels.
    public var maxImageDimension: Int
    /// JPEG quality, 0...1.
    public var jpegQuality: Double
    /// Recording stops on its own after this many seconds.
    public var maxDuration: TimeInterval
    /// Width of the grayscale grid used for perceptual diffs.
    public var signatureGridWidth: Int
    /// Height of the grayscale grid used for perceptual diffs.
    public var signatureGridHeight: Int

    public init(
        maxFrames: Int,
        changeThreshold: Double,
        majorChangeThreshold: Double,
        duplicateThreshold: Double,
        minChangeInterval: TimeInterval,
        eventAssociationWindow: TimeInterval,
        sampleFPS: Double,
        maxImageDimension: Int,
        jpegQuality: Double,
        maxDuration: TimeInterval,
        signatureGridWidth: Int,
        signatureGridHeight: Int
    ) {
        self.maxFrames = maxFrames
        self.changeThreshold = changeThreshold
        self.majorChangeThreshold = majorChangeThreshold
        self.duplicateThreshold = duplicateThreshold
        self.minChangeInterval = minChangeInterval
        self.eventAssociationWindow = eventAssociationWindow
        self.sampleFPS = sampleFPS
        self.maxImageDimension = maxImageDimension
        self.jpegQuality = jpegQuality
        self.maxDuration = maxDuration
        self.signatureGridWidth = signatureGridWidth
        self.signatureGridHeight = signatureGridHeight
    }

    public static let `default` = ClipConfig(
        maxFrames: 16,
        changeThreshold: 0.06,
        majorChangeThreshold: 0.18,
        duplicateThreshold: 0.015,
        minChangeInterval: 0.35,
        eventAssociationWindow: 0.45,
        sampleFPS: 4,
        maxImageDimension: 1280,
        jpegQuality: 0.72,
        maxDuration: 90,
        signatureGridWidth: 32,
        signatureGridHeight: 18
    )

    public func sanitized() -> ClipConfig {
        var copy = self
        copy.maxFrames = Self.clamp(maxFrames, 1, 40)
        copy.changeThreshold = Self.clamp(changeThreshold, 0.005, 0.9)
        copy.majorChangeThreshold = Self.clamp(majorChangeThreshold, 0.01, 1)
        if copy.majorChangeThreshold < copy.changeThreshold {
            copy.majorChangeThreshold = copy.changeThreshold
        }
        copy.duplicateThreshold = Self.clamp(duplicateThreshold, 0, 0.2)
        copy.minChangeInterval = Self.clamp(minChangeInterval, 0, 5)
        copy.eventAssociationWindow = Self.clamp(eventAssociationWindow, 0.05, 3)
        copy.sampleFPS = Self.clamp(sampleFPS, 1, 15)
        copy.maxImageDimension = Self.clamp(maxImageDimension, 160, 3840)
        copy.jpegQuality = Self.clamp(jpegQuality, 0.3, 0.95)
        copy.maxDuration = Self.clamp(maxDuration, 5, 300)
        copy.signatureGridWidth = Self.clamp(signatureGridWidth, 4, 128)
        copy.signatureGridHeight = Self.clamp(signatureGridHeight, 4, 128)
        return copy
    }

    private static func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
        min(max(value, lower), upper)
    }
}
