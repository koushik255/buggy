#if os(macOS)
import BuggyCore
import CoreGraphics
import Foundation

/// Listen-only event tap for clicks and key-downs. Requires Accessibility permission.
/// Events are reported in Quartz global points (origin at the top-left of the main
/// display, y down), which is the same space as `CGDisplayBounds` and `kCGWindowBounds`.
final class InputMonitor {
    struct RawEvent {
        enum Kind {
            case click(globalX: Double, globalY: Double, button: MouseButton)
            case key(name: String)
        }

        var time: TimeInterval
        var kind: Kind
    }

    var onEvent: ((RawEvent) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let clock: () -> TimeInterval

    init(clock: @escaping () -> TimeInterval) {
        self.clock = clock
    }

    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = eventBit(.leftMouseDown) | eventBit(.rightMouseDown) | eventBit(.otherMouseDown) | eventBit(.keyDown)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: buggyEventTap,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.info("event tap was not created; Accessibility permission is probably off")
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            let point = event.location
            let button: MouseButton
            switch type {
            case .rightMouseDown: button = .right
            case .otherMouseDown: button = .other
            default: button = .left
            }
            onEvent?(RawEvent(
                time: clock(),
                kind: .click(globalX: point.x, globalY: point.y, button: button)
            ))
        case .keyDown:
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 1 { return }
            guard let name = Self.keyName(from: event) else { return }
            onEvent?(RawEvent(time: clock(), kind: .key(name: name)))
        default:
            break
        }
    }

    private func eventBit(_ type: CGEventType) -> CGEventMask {
        CGEventMask(1) << CGEventMask(type.rawValue)
    }

    private static let ignoredKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    private static func keyName(from event: CGEvent) -> String? {
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if ignoredKeyCodes.contains(code) { return nil }
        let base = keyNames[code] ?? "key\(code)"
        let flags = event.flags
        var parts = [String]()
        if flags.contains(.maskControl) { parts.append("Control") }
        if flags.contains(.maskAlternate) { parts.append("Option") }
        if flags.contains(.maskShift) { parts.append("Shift") }
        if flags.contains(.maskCommand) { parts.append("Command") }
        parts.append(base)
        return parts.joined(separator: "+")
    }

    private static let keyNames: [UInt16: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p",
        37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "n", 46: "m", 47: ".", 50: "`",
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
        76: "KeypadEnter", 117: "ForwardDelete",
        115: "Home", 119: "End", 116: "PageUp", 121: "PageDown",
        123: "Left", 124: "Right", 125: "Down", 126: "Up",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}

private func buggyEventTap(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let userInfo {
        let monitor = Unmanaged<InputMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        monitor.handle(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}
#endif
