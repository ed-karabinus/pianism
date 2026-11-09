import SwiftUI

/// The grey for the app's secondary text. In light mode the system's grey is about 3.4:1 on white, under the 4.5:1
/// the accessibility audit asks of text (#165), so this one is darker: about 5.1:1 on white and 4.6:1 on a form's
/// grey, and darker still with Increase Contrast. Dark mode keeps the system's, which passes.
struct SecondaryText: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color {
        if environment.colorScheme == .dark { return .secondary }
        return environment.colorSchemeContrast == .increased ? Self.increased : Self.light
    }

    static let light = Color(red: 0x6C / 255, green: 0x6C / 255, blue: 0x70 / 255)
    static let increased = Color(red: 0x48 / 255, green: 0x48 / 255, blue: 0x4A / 255)
}

extension ShapeStyle where Self == SecondaryText {
    static var secondaryText: SecondaryText { SecondaryText() }
}
