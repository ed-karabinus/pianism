// swift-tools-version: 6.2

import PackageDescription

// PianismPurchases implements the core's Pro port with StoreKit, and is the only package that imports it (ADR 0012).

/// Warnings are errors in every target, wherever the package is built from.
let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
    name: "PianismPurchases",
    platforms: [
        .iOS(.v26),
        .macOS(.v15),
    ],
    products: [
        .library(name: "PianismPurchases", targets: ["PianismPurchases"])
    ],
    dependencies: [
        .package(path: "../PianismCore")
    ],
    targets: [
        .target(
            name: "PianismPurchases",
            dependencies: [.product(name: "PianismCore", package: "PianismCore")],
            swiftSettings: strict
        ),
        .testTarget(
            name: "PianismPurchasesTests",
            dependencies: ["PianismPurchases"],
            swiftSettings: strict
        ),
    ]
)
