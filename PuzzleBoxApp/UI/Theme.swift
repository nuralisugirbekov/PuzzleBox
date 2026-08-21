import SwiftUI

/// Dark "gaming station" design system: near-black backgrounds, dark card
/// surfaces with hairline strokes, and a neon lime primary accent.
enum Theme {
    static let background = Color(red: 0.047, green: 0.055, blue: 0.078)   // #0C0E14
    static let surface = Color(red: 0.086, green: 0.102, blue: 0.145)      // #161A25
    static let surfaceHigh = Color(red: 0.129, green: 0.153, blue: 0.208)  // #212735
    static let neon = Color(red: 0.776, green: 0.953, blue: 0.114)         // #C6F31D
    static let textSecondary = Color(white: 0.62)
    static let stroke = Color.white.opacity(0.07)
}

extension View {
    /// Standard dark card: surface fill, rounded corners, hairline stroke.
    func themeCard(cornerRadius: CGFloat = 18) -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            }
    }

    /// Soft neon glow for accent elements.
    func neonGlow(_ opacity: Double = 0.35) -> some View {
        shadow(color: Theme.neon.opacity(opacity), radius: 12, y: 2)
    }
}
