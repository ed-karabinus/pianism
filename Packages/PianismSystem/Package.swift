// swift-tools-version: 6.2

import PackageDescription

// PianismSystem implements the core's ports with the system's services, such as notifications (SES-3).
// Its tests run on macOS; posting a notification needs an app, so the end-to-end tests cover that.

/// Warnings are errors in every target, wherever the package is built from.
let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
    name: "PianismSystem",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        .macOS(.v15),
    ],
    products: [
        .library(name: "PianismSystem", targets: ["PianismSystem"])
    ],
    dependencies: [
        .package(path: "../PianismCore")
    ],
    targets: [
        .target(
            name: "PianismSystem",
            dependencies: [
                .product(name: "PianismCore", package: "PianismCore")
            ],
            resources: [.process("Resources")],
            swiftSettings: strict
        ),
        .testTarget(
            name: "PianismSystemTests",
            dependencies: ["PianismSystem"],
            swiftSettings: strict
        ),
    ]
)
