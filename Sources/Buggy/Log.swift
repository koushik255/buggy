#if os(macOS)
import Darwin
import Foundation

enum Log {
    static func info(_ message: String) {
        fputs("Buggy: \(message)\n", stderr)
    }
}
#endif
