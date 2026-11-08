import SwiftUI
import Testing

@testable import PianismFeatures

struct SecondaryTextTests {
    @Test("#165: in light mode, secondary text is 4.5:1 on white and a form's grey, and more with Increase Contrast")
    func contrast() {
        var light = EnvironmentValues()
        light.colorScheme = .light
        let white = Color.white
        let formGrey = Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255)
        let text = SecondaryText().resolve(in: light)

        #expect(ratio(text, white, in: light) >= 4.5)
        #expect(ratio(text, formGrey, in: light) >= 4.5)
        #expect(ratio(SecondaryText.increased, formGrey, in: light) >= 7)
    }

    /// WCAG's contrast ratio between two opaque colours.
    private func ratio(_ first: Color, _ second: Color, in environment: EnvironmentValues) -> Double {
        let lighter = [first, second].map { luminance($0.resolve(in: environment)) }.sorted(by: >)
        return (lighter[0] + 0.05) / (lighter[1] + 0.05)
    }

    private func luminance(_ color: Color.Resolved) -> Double {
        0.2126 * Double(color.linearRed) + 0.7152 * Double(color.linearGreen) + 0.0722 * Double(color.linearBlue)
    }
}
