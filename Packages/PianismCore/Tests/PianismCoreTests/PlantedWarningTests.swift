import Foundation
import Testing

// Planted for #24: with Swift 6.4, as in the Linux job, this capture is only a warning, even with
// warnings as errors, so CI must fail on it. (Swift 6.2, in the macOS jobs, already makes it an error.)
// The next commit removes this file.
final class PlantedBox { var count = 0 }

@Test func plantedPreconcurrencyCapture() {
    let box = PlantedBox()
    DispatchQueue.concurrentPerform(iterations: 2) { _ in box.count += 1 }
}
