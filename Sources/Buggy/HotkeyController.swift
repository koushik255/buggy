#if os(macOS)
import Carbon
import Foundation

/// System-wide Control-Option-B. Carbon hotkeys work while another app is focused
/// and do not themselves require Accessibility permission.
final class HotkeyController {
    var onPress: (() -> Void)?
    private(set) var isInstalled = false
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func install() -> Bool {
        guard !isInstalled else { return true }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            buggyHotKeyHandler,
            1,
            &spec,
            pointer,
            &handler
        )
        guard installStatus == noErr else {
            Log.info("hotkey handler failed (\(installStatus))")
            return false
        }

        let hotKeyID = EventHotKeyID(signature: fourCharCode("BGGY"), id: 1)
        let modifiers = UInt32(controlKey) | UInt32(optionKey)
        var registered: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_B),
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &registered
        )
        guard registerStatus == noErr, registered != nil else {
            Log.info("hotkey registration failed (\(registerStatus))")
            return false
        }
        hotKey = registered
        isInstalled = true
        return true
    }

    func uninstall() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        hotKey = nil
        if let handler {
            RemoveEventHandler(handler)
        }
        handler = nil
        isInstalled = false
    }

    fileprivate func fire() {
        onPress?()
    }
}

private func fourCharCode(_ string: String) -> UInt32 {
    var result: UInt32 = 0
    for byte in string.utf8.prefix(4) {
        result = (result << 8) | UInt32(byte)
    }
    return result
}

private func buggyHotKeyHandler(
    _ call: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return noErr }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        UInt32(kEventParamDirectObject),
        UInt32(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.id == 1 else { return status }
    let controller = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        controller.fire()
    }
    return noErr
}
#endif
