// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Renamer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Renamer",
            path: "Sources/Renamer",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=minimal"])
            ]
        )
    ]
)
