// swift-tools-version: 6.2

import PackageDescription

// PianismAnalytics implements the core's analytics port with TelemetryDeck, and is the only package that depends on
// it (E5, ADR 0011). Its version is exact, so a new one arrives only by a reviewed change.

/// Warnings are errors in every target, wherever the package is built from.
let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
    name: "PianismAnalytics",
    platforms: [
        .iOS(.v26),
        .macOS(.v15),
    ],
    products: [
        .library(name: "PianismAnalytics", targets: ["PianismAnalytics"])
    ],
    dependencies: [
        .package(path: "../PianismCore"),
        .package(url: "https://github.com/TelemetryDeck/SwiftSDK", exact: "2.14.2"),
    ],
    targets: [
        .target(
            name: "PianismAnalytics",
            dependencies: [
                .product(name: "PianismCore", package: "PianismCore"),
                .product(name: "TelemetryDeck", package: "SwiftSDK"),
            ],
            swiftSettings: strict
        ),
        .testTarget(
            name: "PianismAnalyticsTests",
            dependencies: [
                "PianismAnalytics",
                .product(name: "TelemetryDeck", package: "SwiftSDK"),
            ],
            swiftSettings: strict
        ),
    ]
)
