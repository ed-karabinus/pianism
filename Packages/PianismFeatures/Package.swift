// swift-tools-version: 6.2

import PackageDescription

// PianismFeatures holds the SwiftUI screens and their view models.
// It depends on PianismCore for every rule; adapters are injected by the app target.

/// Warnings are errors in every target, wherever the package is built from.
let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
    name: "PianismFeatures",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(name: "PianismFeatures", targets: ["PianismFeatures"])
    ],
    dependencies: [
        .package(path: "../PianismCore")
    ],
    targets: [
        .target(
            name: "PianismFeatures",
            dependencies: [
                .product(name: "PianismCore", package: "PianismCore")
            ],
            resources: [.process("Resources")],
            swiftSettings: strict
        )
    ]
)
