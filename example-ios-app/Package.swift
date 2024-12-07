// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// This + Sources folder only exists to appease swiftc + sourcekit-lsp
let package = Package(
    name: "MyPackage",
    platforms: [.macOS("15.1")],
    targets: [
        .target(name: "Log", path: "Log"),
        .target(name: "JsWrap", path: "JsWrap"),
        .target(name: "JsWrapExample", path: "JsWrapExample"),
    ]
)
