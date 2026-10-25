// swift-tools-version: 6.2

import PackageDescription

// PianismMIDI hears the keys struck on every connected piano, over CoreMIDI (MIDI-1). Its tests run on macOS with
// virtual sources; the simulator has no MIDI, so a real piano is checked on a device (docs/device-checklist.md).

/// Warnings are errors in every target, wherever the package is built from.
let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
    name: "PianismMIDI",
    platforms: [
        .iOS(.v26),
        .macOS(.v15),
    ],
    products: [
        .library(name: "PianismMIDI", targets: ["PianismMIDI"])
    ],
    dependencies: [
        .package(path: "../PianismCore")
    ],
    targets: [
        .target(
            name: "PianismMIDI",
            dependencies: [
                .product(name: "PianismCore", package: "PianismCore")
            ],
            swiftSettings: strict
        ),
        .testTarget(
            name: "PianismMIDITests",
            dependencies: [
                "PianismMIDI",
                .product(name: "PianismCoreTestSupport", package: "PianismCore"),
            ],
            swiftSettings: strict
        ),
    ]
)
