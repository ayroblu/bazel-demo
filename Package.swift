// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "bazel-project",
    platforms: [.macOS(.v15)],
    dependencies: [
        // Replace these entries with your dependencies.
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.12.0")
    ]
)
