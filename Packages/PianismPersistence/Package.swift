// swift-tools-version: 6.2

import PackageDescription

// PianismPersistence implements the core's storage ports on Apple platforms.
// It needs Foundation APIs that Linux lacks, such as NSFileCoordinator, so its tests run on macOS
// (see docs/adr/0003).

/// Warnings are errors in every target, wherever the package is built from.
let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
    name: "PianismPersistence",
    platforms: [
        .iOS(.v26),
        .macOS(.v15),
    ],
    products: [
        .library(name: "PianismPersistence", targets: ["PianismPersistence"])
    ],
    dependencies: [
        .package(path: "../PianismCore")
    ],
    targets: [
        .target(
            name: "PianismPersistence",
            dependencies: [
                .product(name: "PianismCore", package: "PianismCore")
            ],
            swiftSettings: strict
        ),
        .testTarget(
            name: "PianismPersistenceTests",
            dependencies: [
                "PianismPersistence",
                .product(name: "PianismCore", package: "PianismCore"),
                .product(name: "PianismCoreTestSupport", package: "PianismCore"),
            ],
            resources: [.copy("Fixtures")],
            swiftSettings: strict
        ),
    ]
)
