// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// This + Sources folder only exists to appease swiftc + sourcekit-lsp
let package = Package(
    name: "MyPackage",
    targets: [
        .target(name: "Log", path: "Log"),
        .target(name: "JsWrap", dependencies: ["Log"], path: "JsWrap"),
        .target(name: "JsWrapExample", dependencies: ["JsWrap"], path: "JsWrapExample"),
    ]
)
