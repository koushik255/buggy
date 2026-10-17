#if os(macOS)
import AppKit
import Foundation

struct DisplayChoice: Equatable {
    var id: UInt32
    var name: String
    var isMain: Bool
}

struct WindowChoice: Equatable {
    var id: UInt32
    var title: String
}

struct MenuState {
    var isRecording: Bool
    var elapsed: TimeInterval
    var statusText: String
    var maxFrames: Int
    var displays: [DisplayChoice]
    var windows: [WindowChoice]
    var choice: CaptureChoice
    var canReveal: Bool
    var screenRecordingGranted: Bool
    var accessibilityGranted: Bool
    var hotkeyInstalled: Bool
    var targetSummary: String
}

final class MenuBarController: NSObject, NSMenuDelegate {
    var onToggle: (() -> Void)?
    var onReveal: (() -> Void)?
    var onCopy: (() -> Void)?
    var onOpenFolder: (() -> Void)?
    var onQuit: (() -> Void)?
    var onSelectDisplay: ((UInt32) -> Void)?
    var onSelectWindow: ((UInt32) -> Void)?
    var onSelectMaxFrames: ((Int) -> Void)?
    var onMenuOpen: (() -> Void)?

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private var state = MenuState(
        isRecording: false,
        elapsed: 0,
        statusText: "Idle",
        maxFrames: 16,
        displays: [],
        windows: [],
        choice: .display(0),
        canReveal: false,
        screenRecordingGranted: false,
        accessibilityGranted: false,
        hotkeyInstalled: false,
        targetSummary: "This Display"
    )
    private var menuIsOpen = false

    func install() {
        menu.delegate = self
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.menu = menu
        statusItem = item
        applyIcon()
        rebuild()
    }

    func update(_ state: MenuState) {
        self.state = state
        applyIcon()
        if !menuIsOpen {
            rebuild()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        rebuild()
        onMenuOpen?()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        rebuild()
    }

    private func applyIcon() {
        guard let button = statusItem?.button else { return }
        let symbol = state.isRecording ? "record.circle.fill" : "ladybug"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Buggy")
        button.image?.isTemplate = !state.isRecording
        if state.isRecording {
            statusItem?.length = NSStatusItem.variableLength
            button.title = " " + ClipTextSeconds.string(state.elapsed)
        } else {
            statusItem?.length = NSStatusItem.squareLength
            button.title = ""
        }
    }

    private func rebuild() {
        menu.removeAllItems()
        let status = NSMenuItem(title: state.statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let toggleTitle = state.isRecording ? "Clip" : "Ready to Clip"
        let toggle = NSMenuItem(title: "\(toggleTitle)    ⌃⌥B", action: #selector(toggle), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        if !state.hotkeyInstalled {
            let missing = NSMenuItem(title: "Global hotkey unavailable", action: nil, keyEquivalent: "")
            missing.isEnabled = false
            menu.addItem(missing)
        }
        menu.addItem(.separator())

        let capture = NSMenuItem(title: "Capture: \(state.targetSummary)", action: nil, keyEquivalent: "")
        capture.submenu = captureMenu()
        menu.addItem(capture)

        let frames = NSMenuItem(title: "Max Frames", action: nil, keyEquivalent: "")
        frames.submenu = frameMenu()
        menu.addItem(frames)
        menu.addItem(.separator())

        let reveal = NSMenuItem(title: "Reveal Last Clip in Finder", action: #selector(reveal), keyEquivalent: "")
        reveal.target = self
        reveal.isEnabled = state.canReveal && !state.isRecording
        menu.addItem(reveal)
        let copy = NSMenuItem(title: "Copy Markdown", action: #selector(copyMarkdown), keyEquivalent: "")
        copy.target = self
        copy.isEnabled = state.canReveal && !state.isRecording
        menu.addItem(copy)
        let folder = NSMenuItem(title: "Open Clips Folder", action: #selector(openFolder), keyEquivalent: "")
        folder.target = self
        folder.isEnabled = !state.isRecording
        menu.addItem(folder)
        menu.addItem(.separator())

        let screen = NSMenuItem(
            title: state.screenRecordingGranted ? "Screen Recording: Granted" : "Screen Recording: Not Granted",
            action: nil,
            keyEquivalent: ""
        )
        screen.isEnabled = false
        menu.addItem(screen)
        let access = NSMenuItem(
            title: state.accessibilityGranted ? "Accessibility: Granted" : "Accessibility: Off (clicks not marked)",
            action: nil,
            keyEquivalent: ""
        )
        access.isEnabled = false
        menu.addItem(access)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Buggy", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func captureMenu() -> NSMenu {
        let menu = NSMenu()
        let displays = NSMenuItem(title: "Displays", action: nil, keyEquivalent: "")
        displays.isEnabled = false
        menu.addItem(displays)
        if state.displays.isEmpty {
            let empty = NSMenuItem(title: "Grant Screen Recording to list displays", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for display in state.displays {
                let item = NSMenuItem(title: display.name, action: #selector(selectDisplay(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = NSNumber(value: display.id)
                item.state = isSelected(display: display.id) ? .on : .off
                item.isEnabled = !state.isRecording
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let windows = NSMenuItem(title: "Windows", action: nil, keyEquivalent: "")
        windows.isEnabled = false
        menu.addItem(windows)
        if state.windows.isEmpty {
            let empty = NSMenuItem(title: "No windows yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for window in state.windows.prefix(40) {
                let item = NSMenuItem(title: window.title, action: #selector(selectWindow(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = NSNumber(value: window.id)
                item.state = isSelected(window: window.id) ? .on : .off
                item.isEnabled = !state.isRecording
                menu.addItem(item)
            }
        }
        return menu
    }

    private func frameMenu() -> NSMenu {
        let menu = NSMenu()
        for count in Settings.frameChoices {
            let item = NSMenuItem(title: "\(count)", action: #selector(selectMaxFrames(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: count)
            item.state = count == state.maxFrames ? .on : .off
            item.isEnabled = !state.isRecording
            menu.addItem(item)
        }
        if !Settings.frameChoices.contains(state.maxFrames) {
            let custom = NSMenuItem(title: "Custom (\(state.maxFrames))", action: nil, keyEquivalent: "")
            custom.state = .on
            custom.isEnabled = false
            menu.addItem(custom)
        }
        return menu
    }

    private func isSelected(display id: UInt32) -> Bool {
        if case .display(let selected) = state.choice { return selected == id }
        return false
    }

    private func isSelected(window id: UInt32) -> Bool {
        if case .window(let selected) = state.choice { return selected == id }
        return false
    }

    @objc private func toggle() { onToggle?() }
    @objc private func reveal() { onReveal?() }
    @objc private func copyMarkdown() { onCopy?() }
    @objc private func openFolder() { onOpenFolder?() }
    @objc private func quit() { onQuit?() }

    @objc private func selectDisplay(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        onSelectDisplay?(number.uint32Value)
    }

    @objc private func selectWindow(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        onSelectWindow?(number.uint32Value)
    }

    @objc private func selectMaxFrames(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        onSelectMaxFrames?(number.intValue)
    }
}

private enum ClipTextSeconds {
    static func string(_ value: TimeInterval) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
#endif
