// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OTPGrabberMenuBar",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "OTPGrabberMenuBarCore", targets: ["OTPGrabberMenuBarCore"]),
        .executable(name: "OTPGrabberMenuBar", targets: ["OTPGrabberMenuBar"]),
    ],
    targets: [
        .target(
            name: "OTPGrabberMenuBarCore",
            path: "Sources/OTPGrabberMenuBarCore"
        ),
        .executableTarget(
            name: "OTPGrabberMenuBar",
            dependencies: ["OTPGrabberMenuBarCore"],
            path: "Sources/OTPGrabberMenuBar"
        ),
        .executableTarget(
            name: "OTPGrabberMenuBarChecks",
            dependencies: ["OTPGrabberMenuBarCore"],
            path: "Sources/OTPGrabberMenuBarChecks"
        ),
        .testTarget(
            name: "OTPGrabberMenuBarTests",
            dependencies: ["OTPGrabberMenuBarCore"],
            path: "Tests/OTPGrabberMenuBarTests"
        ),
    ]
)
