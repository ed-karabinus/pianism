// swift-tools-version: 6.2

import PackageDescription

// PianismGlance holds what the app and the widget extension must both name (ADR 0010). It is
// iOS-only, as the extension is, so it stays out of `make test-adapters`.

/// Warnings are errors in every target, wherever the package is built from.
let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
    name: "PianismGlance",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(name: "PianismGlance", targets: ["PianismGlance"])
    ],
    dependencies: [
        .package(path: "../PianismCore")
    ],
    targets: [
        .target(
            name: "PianismGlance",
            dependencies: [
                .product(name: "PianismCore", package: "PianismCore")
            ],
            swiftSettings: strict
        )
    ]
)
