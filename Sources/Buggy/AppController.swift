#if os(macOS)
import AppKit
import BuggyCore
import CoreGraphics
import Foundation
import ScreenCaptureKit

@MainActor
final class AppController {
    private let menu = MenuBarController()
    private let hotkey = HotkeyController()
    private var settings = Settings.load()
    private var engine: CaptureEngine?
    private var input: InputMonitor?
    private var displays: [DisplayChoice] = []
    private var windows: [WindowChoice] = []
    private var recording = false
    private var busy = false
    private var stopping = false
    private var inputMonitoring = false
    private var activeLabel = "Display"
    private var targetSummary = "This Display"
    private var statusLine = "Idle"
    private var timer: Timer?
    private var lastClipURL: URL?
    private var hotkeyInstalled = false

    func start() {
        if let path = settings.lastClipPath {
            lastClipURL = URL(fileURLWithPath: path, isDirectory: true)
        }
        menu.onToggle = { [weak self] in self?.toggle() }
        menu.onReveal = { [weak self] in self?.reveal() }
        menu.onCopy = { [weak self] in self?.copyMarkdown() }
        menu.onOpenFolder = { [weak self] in self?.openFolder() }
        menu.onQuit = { NSApp.terminate(nil) }
        menu.onSelectDisplay = { [weak self] id in self?.selectDisplay(id) }
        menu.onSelectWindow = { [weak self] id in self?.selectWindow(id) }
        menu.onSelectMaxFrames = { [weak self] count in self?.selectMaxFrames(count) }
        menu.onMenuOpen = { [weak self] in
            Task { await self?.refreshContent() }
        }
        menu.install()
        hotkey.onPress = { [weak self] in
            Task { @MainActor in self?.toggle() }
        }
        hotkeyInstalled = hotkey.install()
        updateSummary()
        render()
        Task { await refreshContent() }
        Log.info("ready")
    }

    func shutdown() {
        timer?.invalidate()
        input?.stop()
        hotkey.uninstall()
    }

    private func toggle() {
        if recording {
            Task { await stopRecording() }
        } else {
            Task { await startRecording() }
        }
    }

    private func startRecording() async {
        guard !recording, !busy, !stopping else { return }
        busy = true
        defer { busy = false }

        guard ensureScreenRecording() else { return }
        let decision = decideInput()
        guard decision != .abort else { return }

        let config = settings.makeConfig()
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            displays = Self.displayChoices(from: content)
            windows = Self.windowChoices(from: content)
            let setup = try resolve(in: content, config: config)
            let engine = CaptureEngine()
            engine.onAutoStop = { [weak self] in
                Task { @MainActor in await self?.stopRecording() }
            }
            try await engine.start(
                filter: setup.filter,
                rect: setup.rect,
                pixelWidth: setup.pixelWidth,
                pixelHeight: setup.pixelHeight,
                config: config
            )
            self.engine = engine
            activeLabel = setup.label
            inputMonitoring = false
            if decision == .monitor {
                let monitor = InputMonitor { [weak engine] in engine?.elapsed() ?? 0 }
                monitor.onEvent = { [weak engine] event in engine?.add(event) }
                inputMonitoring = monitor.start()
                input = monitor
                if !inputMonitoring {
                    Log.info("continuing without click and key marks")
                }
            }
            recording = true
            statusLine = "Recording"
            beginTimer()
            render()
        } catch {
            input?.stop()
            input = nil
            self.engine = nil
            present(error: error)
            render()
        }
    }

    private func stopRecording() async {
        guard recording, !stopping, let engine else { return }
        stopping = true
        timer?.invalidate()
        timer = nil
        input?.stop()
        input = nil
        statusLine = "Saving clip…"
        render()
        let capture = await engine.stop()
        let label = activeLabel
        let monitoring = inputMonitoring
        let config = settings.makeConfig()
        recording = false
        self.engine = nil
        stopping = false
        do {
            let output = try ClipExporter.export(
                capture: capture,
                config: config,
                captureLabel: label,
                inputMonitoringEnabled: monitoring
            )
            lastClipURL = output.directory
            settings.lastClipPath = output.directory.path
            settings.save()
            statusLine = "Saved \(output.frameCount) frames"
            render()
            offer(output)
        } catch {
            statusLine = "Clip failed"
            render()
            present(error: error)
        }
    }

    private func beginTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.render() }
        }
    }

    private func ensureScreenRecording() -> Bool {
        if Permissions.screenRecording { return true }
        _ = Permissions.requestScreenRecording()
        if Permissions.screenRecording { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = """
        Enable Buggy in System Settings → Privacy & Security → Screen Recording.

        If you just turned it on, quit Buggy and open it again. macOS applies Screen Recording permission on the next launch.
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Quit Buggy")
        alert.addButton(withTitle: "Cancel")
        switch present(alert) {
        case .alertFirstButtonReturn:
            Permissions.openScreenRecordingSettings()
        case .alertSecondButtonReturn:
            NSApp.terminate(nil)
        default:
            break
        }
        return false
    }

    private func decideInput() -> InputDecision {
        if Permissions.accessibility { return .monitor }
        guard !settings.suppressAccessibilityAlert else { return .skip }
        Permissions.promptAccessibility()
        if Permissions.accessibility { return .monitor }

        let alert = NSAlert()
        alert.messageText = "Mark clicks and keys?"
        alert.informativeText = """
        Accessibility permission lets Buggy record clicks and key presses and draw each click on the frame where it happened.

        Without it, Buggy still keeps a frame when the screen changes.
        """
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "Clip Without Clicks")
        alert.addButton(withTitle: "Cancel")
        switch present(alert) {
        case .alertFirstButtonReturn:
            Permissions.openAccessibilitySettings()
            return Permissions.accessibility ? .monitor : .abort
        case .alertSecondButtonReturn:
            settings.suppressAccessibilityAlert = true
            settings.save()
            return .skip
        default:
            return .abort
        }
    }

    private func offer(_ output: ClipOutput) {
        let alert = NSAlert()
        alert.messageText = "Clip saved"
        alert.informativeText = "\(output.frameCount) frames\n\(output.directory.path)"
        alert.addButton(withTitle: "Reveal in Finder")
        alert.addButton(withTitle: "Copy Markdown")
        alert.addButton(withTitle: "Done")
        switch present(alert) {
        case .alertFirstButtonReturn:
            reveal()
        case .alertSecondButtonReturn:
            copy(output.markdown)
        default:
            break
        }
    }

    private func reveal() {
        guard let directory = lastClipURL else { return }
        let note = directory.appendingPathComponent("clip.md")
        if FileManager.default.fileExists(atPath: note.path) {
            NSWorkspace.shared.activateFileViewerSelecting([note])
        } else if FileManager.default.fileExists(atPath: directory.path) {
            NSWorkspace.shared.open(directory)
        } else {
            present(error: ExportError.unreadable)
        }
    }

    private func copyMarkdown() {
        guard let directory = lastClipURL else { return }
        let note = directory.appendingPathComponent("clip.md")
        guard let text = try? String(contentsOf: note, encoding: .utf8) else {
            present(error: ExportError.unreadable)
            return
        }
        copy(text)
    }

    private func copy(_ markdown: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(markdown, forType: .string)
        statusLine = "Markdown copied"
        render()
    }

    private func openFolder() {
        do {
            NSWorkspace.shared.open(try ClipExporter.clipsDirectory())
        } catch {
            present(error: error)
        }
    }

    private func selectDisplay(_ id: UInt32) {
        settings.choice = .display(id)
        settings.save()
        updateSummary()
        render()
    }

    private func selectWindow(_ id: UInt32) {
        settings.choice = .window(id)
        settings.save()
        updateSummary()
        render()
    }

    private func selectMaxFrames(_ count: Int) {
        settings.maxFrames = count
        settings.save()
        render()
    }

    private func refreshContent() async {
        guard Permissions.screenRecording else {
            displays = []
            windows = []
            render()
            return
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            displays = Self.displayChoices(from: content)
            windows = Self.windowChoices(from: content)
            updateSummary()
            render()
        } catch {
            if !recording {
                statusLine = error.localizedDescription
                render()
            }
            Log.info("could not list screens: \(error.localizedDescription)")
        }
    }

    private func resolve(in content: SCShareableContent, config: ClipConfig) throws -> CaptureSetup {
        switch settings.choice {
        case .display(let id):
            let display = content.displays.first { $0.displayID == id }
                ?? content.displays.first { $0.displayID == CGMainDisplayID() }
                ?? content.displays.first
            guard let display else { throw CaptureError.noDisplay }
            let fitted = ImageScale.fittedSize(
                width: display.width,
                height: display.height,
                maxDimension: config.maxImageDimension
            )
            return CaptureSetup(
                filter: SCContentFilter(display: display, excludingWindows: []),
                rect: QuartzFrames.displayRect(displayID: display.displayID),
                pixelWidth: fitted.width,
                pixelHeight: fitted.height,
                label: displayName(display.displayID)
            )
        case .window(let id):
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                throw CaptureError.windowUnavailable
            }
            let rect = QuartzFrames.windowRect(windowID: window.windowID, fallback: window.frame)
            let pixels = pixelSize(windowRect: rect, displays: content.displays)
            let fitted = ImageScale.fittedSize(
                width: pixels.width,
                height: pixels.height,
                maxDimension: config.maxImageDimension
            )
            return CaptureSetup(
                filter: SCContentFilter(desktopIndependentWindow: window),
                rect: rect,
                pixelWidth: fitted.width,
                pixelHeight: fitted.height,
                label: windowLabel(window)
            )
        }
    }

    private func pixelSize(windowRect: GlobalRect, displays: [SCDisplay]) -> (width: Int, height: Int) {
        let centerX = windowRect.x + windowRect.width / 2
        let centerY = windowRect.y + windowRect.height / 2
        let display = displays.first { display in
            let rect = QuartzFrames.displayRect(displayID: display.displayID)
            return centerX >= rect.x && centerY >= rect.y
                && centerX < rect.x + rect.width && centerY < rect.y + rect.height
        } ?? displays.first
        let scale: Double
        if let display {
            let rect = QuartzFrames.displayRect(displayID: display.displayID)
            scale = rect.width > 0 ? Double(display.width) / rect.width : 2
        } else {
            scale = Double(NSScreen.main?.backingScaleFactor ?? 2)
        }
        return (
            max(1, Int((windowRect.width * scale).rounded())),
            max(1, Int((windowRect.height * scale).rounded()))
        )
    }

    private func updateSummary() {
        switch settings.choice {
        case .display(let id):
            targetSummary = displays.first { $0.id == id }?.name ?? displayName(id)
        case .window(let id):
            targetSummary = windows.first { $0.id == id }?.title ?? "Window"
        }
    }

    private func displayName(_ id: CGDirectDisplayID) -> String {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? NSNumber else {
                continue
            }
            if number.uint32Value == id {
                return screen.localizedName
            }
        }
        if id == CGMainDisplayID() { return "Main Display" }
        return "Display \(id)"
    }

    private func windowLabel(_ window: SCWindow) -> String {
        let app = window.owningApplication?.applicationName ?? "App"
        let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if title.isEmpty { return app }
        return "\(app) — \(title)"
    }

    private static func displayChoices(from content: SCShareableContent) -> [DisplayChoice] {
        let main = CGMainDisplayID()
        return content.displays.map { display in
            DisplayChoice(id: display.displayID, name: liveDisplayName(display.displayID), isMain: display.displayID == main)
        }
        .sorted { lhs, rhs in
            if lhs.isMain != rhs.isMain { return lhs.isMain }
            return lhs.name < rhs.name
        }
    }

    private static func liveDisplayName(_ id: CGDirectDisplayID) -> String {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? NSNumber else {
                continue
            }
            if number.uint32Value == id { return screen.localizedName }
        }
        if id == CGMainDisplayID() { return "Main Display" }
        return "Display \(id)"
    }

    private static func windowChoices(from content: SCShareableContent) -> [WindowChoice] {
        let ownBundle = Bundle.main.bundleIdentifier
        return content.windows.compactMap { window in
            guard window.isOnScreen, window.windowLayer == 0 else { return nil }
            guard window.frame.width >= 80, window.frame.height >= 80 else { return nil }
            if let ownBundle, window.owningApplication?.bundleIdentifier == ownBundle { return nil }
            let app = window.owningApplication?.applicationName ?? "App"
            let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var label = title.isEmpty ? app : "\(app) — \(title)"
            if label.count > 90 {
                label = String(label.prefix(87)) + "..."
            }
            return WindowChoice(id: window.windowID, title: label)
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func render() {
        let elapsed = engine?.elapsed() ?? 0
        let status: String
        if recording {
            status = String(format: "Recording %.1fs", locale: Locale(identifier: "en_US_POSIX"), elapsed)
        } else {
            status = statusLine
        }
        menu.update(MenuState(
            isRecording: recording,
            elapsed: elapsed,
            statusText: status,
            maxFrames: settings.makeConfig().maxFrames,
            displays: displays,
            windows: windows,
            choice: settings.choice,
            canReveal: lastClipURL != nil,
            screenRecordingGranted: Permissions.screenRecording,
            accessibilityGranted: Permissions.accessibility,
            hotkeyInstalled: hotkeyInstalled,
            targetSummary: targetSummary
        ))
    }

    @discardableResult
    private func present(_ alert: NSAlert) -> NSApplication.ModalResponse {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        return alert.runModal()
    }

    private func present(error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Buggy"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        present(alert)
    }
}

private enum InputDecision {
    case monitor
    case skip
    case abort
}

private struct CaptureSetup {
    var filter: SCContentFilter
    var rect: GlobalRect
    var pixelWidth: Int
    var pixelHeight: Int
    var label: String
}
#endif
