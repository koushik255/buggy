// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Buggy",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "BuggyCore", targets: ["BuggyCore"]),
        .executable(name: "Buggy", targets: ["Buggy"]),
    ],
    targets: [
        .target(name: "BuggyCore"),
        .executableTarget(
            name: "Buggy",
            dependencies: ["BuggyCore"],
            linkerSettings: [
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("ScreenCaptureKit", .when(platforms: [.macOS])),
                .linkedFramework("CoreMedia", .when(platforms: [.macOS])),
                .linkedFramework("CoreVideo", .when(platforms: [.macOS])),
                .linkedFramework("CoreGraphics", .when(platforms: [.macOS])),
                .linkedFramework("ImageIO", .when(platforms: [.macOS])),
                .linkedFramework("Carbon", .when(platforms: [.macOS])),
                .linkedFramework("ApplicationServices", .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "BuggyCoreTests",
            dependencies: ["BuggyCore"]
        ),
    ]
)
