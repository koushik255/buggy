import Foundation

#if os(macOS)
import AppKit

@main
enum BuggyMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }
}
#else
@main
enum BuggyMain {
    static func main() {
        let message = "Buggy is a macOS menu-bar app and does not run on this platform.\n"
        try? FileHandle.standardError.write(contentsOf: Data(message.utf8))
        exit(1)
    }
}
#endif
