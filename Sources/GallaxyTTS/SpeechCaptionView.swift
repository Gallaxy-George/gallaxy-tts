import SwiftUI

/// A stable subtitle surface: no typewriter animation or crossfade that would
/// obscure punctuation while the reader follows the spoken phrase.
struct SpeechCaptionView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 34, weight: .semibold, design: .rounded))
            .foregroundStyle(GallaxyBrand.textMain)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .lineLimit(4)
            .minimumScaleFactor(0.35)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 8)
            .background(GallaxyBrand.panelSurface, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("Spoken caption")
            .accessibilityValue(text)
    }
}
