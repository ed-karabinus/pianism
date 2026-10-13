import SwiftUI

/// The app's top-level screen.
///
/// A placeholder until the Practice screen lands in M1 (SES-1).
public struct RootView: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView(
            "Pianism",
            systemImage: "pianokeys",
            description: Text("Your practice log is on its way.")
        )
        .accessibilityIdentifier(AccessibilityID.root)
    }
}

/// Accessibility identifiers shared with the UI tests.
public enum AccessibilityID {
    public static let root = "root"
}

#Preview {
    RootView()
}

#Preview("Dark, AX5") {
    RootView()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
