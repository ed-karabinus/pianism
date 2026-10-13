// swift-tools-version: 6.0

import PackageDescription

// PianismCore holds every rule worth testing. It must stay platform-independent:
// no SwiftUI, SwiftData, CoreMIDI, StoreKit or UIKit (see docs/adr/0001).
// CI builds and tests it on Linux, which enforces that boundary mechanically.
let package = Package(
    name: "PianismCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "PianismCore", targets: ["PianismCore"]),
        .library(name: "PianismCoreTestSupport", targets: ["PianismCoreTestSupport"]),
    ],
    targets: [
        .target(name: "PianismCore"),
        .target(
            name: "PianismCoreTestSupport",
            dependencies: ["PianismCore"]
        ),
        .testTarget(
            name: "PianismCoreTests",
            dependencies: ["PianismCore", "PianismCoreTestSupport"]
        ),
    ]
)
