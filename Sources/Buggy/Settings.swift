#if os(macOS)
import BuggyCore
import CoreGraphics
import Foundation

enum SettingsKey {
    static let maxFrames = "buggy.maxFrames"
    static let captureMode = "buggy.captureMode"
    static let displayID = "buggy.displayID"
    static let windowID = "buggy.windowID"
    static let suppressAccessibilityAlert = "buggy.suppressAccessibilityAlert"
    static let lastClipPath = "buggy.lastClipPath"
    static let changeThreshold = "buggy.changeThreshold"
    static let majorChangeThreshold = "buggy.majorChangeThreshold"
    static let duplicateThreshold = "buggy.duplicateThreshold"
    static let minChangeInterval = "buggy.minChangeInterval"
    static let eventAssociationWindow = "buggy.eventAssociationWindow"
    static let sampleFPS = "buggy.sampleFPS"
    static let maxImageDimension = "buggy.maxImageDimension"
    static let jpegQuality = "buggy.jpegQuality"
    static let maxDuration = "buggy.maxDuration"
}

enum CaptureChoice: Equatable {
    case display(UInt32)
    case window(UInt32)
}

struct Settings {
    var maxFrames: Int
    var choice: CaptureChoice
    var suppressAccessibilityAlert: Bool
    var lastClipPath: String?

    static let frameChoices = [8, 12, 16, 20, 24]

    static func load() -> Settings {
        let defaults = UserDefaults.standard
        let maxFrames = defaults.object(forKey: SettingsKey.maxFrames) as? Int ?? ClipConfig.default.maxFrames
        let mode = defaults.string(forKey: SettingsKey.captureMode) ?? "display"
        let choice: CaptureChoice
        if mode == "window" {
            let windowID = UInt32(defaults.integer(forKey: SettingsKey.windowID))
            choice = .window(windowID)
        } else {
            let stored = defaults.object(forKey: SettingsKey.displayID) as? Int
            let displayID = stored.map { UInt32($0) } ?? CGMainDisplayID()
            choice = .display(displayID)
        }
        return Settings(
            maxFrames: maxFrames,
            choice: choice,
            suppressAccessibilityAlert: defaults.bool(forKey: SettingsKey.suppressAccessibilityAlert),
            lastClipPath: defaults.string(forKey: SettingsKey.lastClipPath)
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(maxFrames, forKey: SettingsKey.maxFrames)
        switch choice {
        case .display(let id):
            defaults.set("display", forKey: SettingsKey.captureMode)
            defaults.set(Int(id), forKey: SettingsKey.displayID)
        case .window(let id):
            defaults.set("window", forKey: SettingsKey.captureMode)
            defaults.set(Int(id), forKey: SettingsKey.windowID)
        }
        defaults.set(suppressAccessibilityAlert, forKey: SettingsKey.suppressAccessibilityAlert)
        defaults.set(lastClipPath, forKey: SettingsKey.lastClipPath)
    }

    func makeConfig() -> ClipConfig {
        let defaults = UserDefaults.standard
        var config = ClipConfig.default
        config.maxFrames = maxFrames
        func override(_ key: String, apply: (Double) -> Void) {
            guard defaults.object(forKey: key) != nil else { return }
            apply(defaults.double(forKey: key))
        }
        override(SettingsKey.changeThreshold) { config.changeThreshold = $0 }
        override(SettingsKey.majorChangeThreshold) { config.majorChangeThreshold = $0 }
        override(SettingsKey.duplicateThreshold) { config.duplicateThreshold = $0 }
        override(SettingsKey.minChangeInterval) { config.minChangeInterval = $0 }
        override(SettingsKey.eventAssociationWindow) { config.eventAssociationWindow = $0 }
        override(SettingsKey.sampleFPS) { config.sampleFPS = $0 }
        override(SettingsKey.jpegQuality) { config.jpegQuality = $0 }
        override(SettingsKey.maxDuration) { config.maxDuration = $0 }
        if defaults.object(forKey: SettingsKey.maxImageDimension) != nil {
            config.maxImageDimension = defaults.integer(forKey: SettingsKey.maxImageDimension)
        }
        return config.sanitized()
    }
}
#endif
