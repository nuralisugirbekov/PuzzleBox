import SwiftUI
import UIKit

/// Game chrome follows the same system surfaces and appearance as the catalog.
/// Playfield art keeps its own colors; these tokens style controls and panels.
enum GameTheme {
    static let background = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let surfaceHigh = Color(uiColor: .tertiarySystemFill)
    static let accent = Color(uiColor: .systemBlue)
    static let ink = Color.primary
    static let textSecondary = Color.secondary
    static let stroke = Color(uiColor: .separator).opacity(0.35)
    static let arena = Color(red: 0.065, green: 0.075, blue: 0.105)
}

extension View {
    func gameCard(cornerRadius: CGFloat = 24) -> some View {
        background(GameTheme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func gameElevation(_ opacity: Double = 0.1) -> some View {
        shadow(color: .black.opacity(min(opacity, 0.1)), radius: 12, y: 4)
    }
}
