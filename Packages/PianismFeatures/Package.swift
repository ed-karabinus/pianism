// swift-tools-version: 6.0

import PackageDescription

// PianismFeatures holds the SwiftUI screens and their view models.
// It depends on PianismCore for every rule; adapters are injected by the app target.
let package = Package(
    name: "PianismFeatures",
    platforms: [
        .iOS(.v18)
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
            ]
        )
    ]
)
