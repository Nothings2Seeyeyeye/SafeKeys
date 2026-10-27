// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SafeKeys",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SafeKeys",
            path: "Sources/SafeKeys"
        )
    ]
)
