// swift-tools-version: 6.2

import PackageDescription

// PianismCore holds every rule worth testing. It must stay platform-independent:
// no SwiftUI, SwiftData, CoreMIDI, StoreKit or UIKit (see docs/adr/0001).
// CI builds and tests it on Linux, which enforces that boundary mechanically.

/// Warnings are errors in every target, wherever the package is built from.
let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
    name: "PianismCore",
    platforms: [
        .iOS(.v26),
        // The core is also tested on the Mac host; macOS 15 is the floor for Synchronization.Mutex.
        .macOS(.v15),
    ],
    products: [
        .library(name: "PianismCore", targets: ["PianismCore"]),
        .library(name: "PianismCoreTestSupport", targets: ["PianismCoreTestSupport"]),
    ],
    targets: [
        .target(name: "PianismCore", swiftSettings: strict),
        .target(
            name: "PianismCoreTestSupport",
            dependencies: ["PianismCore"],
            swiftSettings: strict
        ),
        .testTarget(
            name: "PianismCoreTests",
            dependencies: ["PianismCore", "PianismCoreTestSupport"],
            swiftSettings: strict
        ),
    ]
)
