import PianismFeatures
import SwiftUI

/// The composition root: the only place that wires concrete adapters into the core.
@main
struct PianismApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
