// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Znap",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Znap",
            path: "Sources/Znap"
        ),
    ]
)
