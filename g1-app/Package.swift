// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// This + Sources folder only exists to appease swiftc + sourcekit-lsp
let package = Package(
    name: "MyPackage",
    platforms: [
        .macOS("15.2"), .iOS(.v18),
    ],
    targets: [
        .target(name: "utils", path: "utils"),
        .target(name: "content", path: "content"),
        .target(name: "Log", path: "Log"),
        .target(name: "maps", path: "maps"),
        // .testTarget(name: "utils-test", path: "utils"),
    ]
)
