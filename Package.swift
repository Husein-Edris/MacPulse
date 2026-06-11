// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "MacPulse",
    platforms: [.macOS(.v13)],
    targets: [
        // Note: on a machine with full Xcode, `swift build` works directly.
        // With Command Line Tools only, use `make app` / `make test`, which
        // drive swiftc directly (CLT's SwiftPM can't resolve the platform path).
        .executableTarget(
            name: "MacPulse",
            path: "Sources/MacPulse"
        ),
    ]
)
