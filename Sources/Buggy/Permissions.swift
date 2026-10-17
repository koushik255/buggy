#if os(macOS)
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum Permissions {
    static var screenRecording: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static var accessibility: Bool {
        AXIsProcessTrusted()
    }

    static func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openScreenRecordingSettings() {
        open(urls: [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
        ])
    }

    static func openAccessibilitySettings() {
        open(urls: [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        ])
    }

    private static func open(urls: [String]) {
        for raw in urls {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
#endif
