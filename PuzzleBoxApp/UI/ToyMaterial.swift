import SwiftUI
import UIKit

// "Tactile toy" material shared by redesigned games: one light from the top,
// a lighter face with a soft highlight, a darker lip underneath, a tight
// contact shadow and a wide soft one. Pressed pieces sink into their lip.

extension Color {
    /// A colour that follows light and dark appearance.
    static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: dark.0, green: dark.1, blue: dark.2, alpha: 1)
            : UIColor(red: light.0, green: light.1, blue: light.2, alpha: 1) })
    }

    /// The same hue, lighter (positive) or darker (negative); brightness moves
    /// by `amount` and saturation the other way a little, like real lighting.
    func toyShade(_ amount: Double) -> Color {
        Color(uiColor: UIColor { traits in
            let base = UIColor(self).resolvedColor(with: traits)
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            guard base.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return base }
            return UIColor(hue: h,
                           saturation: max(0, min(1, s - CGFloat(amount) * 0.35)),
                           brightness: max(0, min(1, b + CGFloat(amount))),
                           alpha: a)
        })
    }
}

/// A raised piece: lip, face, highlight and shadows, in any shape.
struct ToyBlock<S: InsettableShape>: View {
    let color: Color
    var shape: S
    /// Height of the darker side under the face, in points.
    var lip: CGFloat = 4
    var pressed = false
    /// Off for pieces that sit on a busy surface and shouldn't cast far.
    var castsShadow = true

    var body: some View {
        let sink = pressed ? lip * 0.6 : 0
        ZStack {
            shape.fill(color.toyShade(-0.2))
                .offset(y: lip)
            shape.fill(LinearGradient(colors: [color.toyShade(0.08), color, color.toyShade(-0.04)],
                                      startPoint: .top, endPoint: .bottom))
                .overlay {
                    // A soft sheen along the top edge.
                    shape.inset(by: 1)
                        .stroke(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0)],
                                               startPoint: .top, endPoint: .center), lineWidth: 1.5)
                }
                .offset(y: sink)
        }
        .padding(.bottom, lip)
        .shadow(color: .black.opacity(castsShadow ? 0.18 : 0), radius: 1, y: lip * 0.5)
        .shadow(color: .black.opacity(castsShadow ? 0.12 : 0), radius: 10, y: lip + 4)
    }
}

/// A well pressed into a surface: darker at the top where the rim shades it.
struct ToySocket<S: InsettableShape>: View {
    let color: Color
    var shape: S

    var body: some View {
        shape.fill(color)
            .overlay {
                shape.fill(LinearGradient(colors: [.black.opacity(0.16), .clear],
                                          startPoint: .top, endPoint: .init(x: 0.5, y: 0.35)))
            }
            .overlay {
                shape.inset(by: 0.5)
                    .stroke(LinearGradient(colors: [.black.opacity(0.12), .white.opacity(0.35)],
                                           startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
    }
}

/// Buttons that sink into their lip while held, with a light tap.
struct ToyPressStyle: ButtonStyle {
    var color: Color
    var lip: CGFloat = 4
    var cornerRadius: CGFloat? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.bottom, lip)
            .background {
                if let cornerRadius {
                    ToyBlock(color: color, shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                             lip: lip, pressed: configuration.isPressed)
                } else {
                    ToyBlock(color: color, shape: Capsule(), lip: lip, pressed: configuration.isPressed)
                }
            }
            .offset(y: configuration.isPressed ? lip * 0.6 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.soft() }
            }
    }
}

/// Round toy button with an SF Symbol, the in-game replacement for the glass
/// header buttons.
struct ToyIconButton: View {
    let symbol: String
    let label: String
    var color: Color = .dynamic(light: (1, 1, 1), dark: (0.26, 0.24, 0.23))
    var ink: Color = .primary
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(ToyPressStyle(color: color, lip: 4, cornerRadius: size / 2))
        .accessibilityLabel(label)
    }
}

// MARK: - In-game HUD

/// What a game drawing its own HUD needs from `GameContainerView`.
struct GameHUD {
    var score: Int = 0
    var best: Int = 0
    var canPause = false
    /// The round's clock as "mm:ss"; read it inside a TimelineView.
    var clock: () -> String = { "00:00" }
    var pause: () -> Void = {}
    var restart: () -> Void = {}
}

extension EnvironmentValues {
    @Entry var gameHUD = GameHUD()
}

/// Where the shared chrome goes: the container's header, or the game's own HUD.
enum GameChrome { case header, inGame }

/// Colours that turn the shared pause, resume and game-over windows into toy
/// cards for a game drawn in the toy material.
struct ToyStyle {
    var card: Color
    var accent: Color
    var ink: Color
    /// The world's clay: secondary buttons and the well the score sits in.
    var tray: Color? = nil
    /// The world's backdrop, to tint the dimmed board behind a window.
    var haze: Color? = nil

    var clay: Color { tray ?? card.toyShade(-0.08) }
}

extension EnvironmentValues {
    @Entry var toyStyle: ToyStyle? = nil
}

// MARK: - Toy worlds

/// The colours of one game's toy world: a soft backdrop, a clay tray with
/// sockets, ink for text, and the windows drawn in the same colours.
struct ToyPalette {
    var backdropTop: Color
    var backdropBottom: Color
    var tray: Color
    var socket: Color
    var ink: Color
    /// Big score letters pressed into the backdrop, and their lit lower rim.
    var deboss: Color
    var debossRim: Color
    var card: Color
    var accent: Color

    var style: ToyStyle { ToyStyle(card: card, accent: accent, ink: ink, tray: tray, haze: backdropBottom) }

    var backdrop: some View {
        LinearGradient(colors: [backdropTop, backdropBottom], startPoint: .top, endPoint: .bottom)
    }
}

/// The score as big letters pressed into the backdrop, the best one below.
struct ToyPressedScore: View {
    let score: Int
    let best: Int
    var deboss: Color
    var rim: Color
    var ink: Color
    /// Changing it plays a little bump, e.g. when points land.
    var bump = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Text(score, format: .number)
                .toyDeboss(deboss, rim: rim)
                .contentTransition(.numericText())
                .animation(.snappy, value: score)
                .lineLimit(1).minimumScaleFactor(0.4)
                .keyframeAnimator(initialValue: CGFloat(1), trigger: bump) { content, scale in
                    content.scaleEffect(scale)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(reduceMotion ? 1 : 1.1, duration: 0.08)
                        SpringKeyframe(1, duration: 0.25)
                    }
                }
            Label {
                Text(L10n.text("Your best") + " · ") + Text(best, format: .number)
            } icon: {
                Image(systemName: "crown.fill")
            }
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .foregroundStyle(ink.opacity(0.7))
        }
        .accessibilityElement(children: .combine)
    }
}


extension View {
    /// Big rounded letters pressed into the backdrop.
    func toyDeboss(_ deboss: Color, rim: Color) -> some View {
        self.font(.system(size: 64, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(deboss)
            .shadow(color: rim, radius: 0, y: 1.5)
            .shadow(color: .black.opacity(0.08), radius: 0, y: -1)
    }

    /// Sets the view in a raised clay tray.
    func toyTray(_ color: Color, cornerRadius: CGFloat = 24, padding: CGFloat = 10) -> some View {
        self.padding(padding)
            .padding(.bottom, 8)
            .background {
                ToyBlock(color: color, shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), lip: 8)
            }
    }
}

/// A small raised capsule for a status value (moves, flags, combo).
struct ToyChip<Content: View>: View {
    var color: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .padding(.bottom, 3)
            .background { ToyBlock(color: color, shape: Capsule(), lip: 3) }
    }
}

/// A capsule toy button with a label, for game tools (hint, notes, extra tube).
struct ToyCapsuleButton: View {
    let title: String
    let symbol: String
    var color: Color
    var ink: Color
    /// A count shown in a small accent bead on the corner (hints left).
    var badge: Int? = nil
    var badgeColor: Color = .accentColor
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(ink)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 38)
                .contentShape(Capsule())
        }
        .buttonStyle(ToyPressStyle(color: color, lip: 4))
        .overlay(alignment: .topTrailing) {
            if let badge {
                Text(badge, format: .number)
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(minWidth: 22, minHeight: 22)
                    .padding(.bottom, 2)
                    .background { ToyBlock(color: badgeColor, shape: Circle(), lip: 2) }
                    .offset(x: 4, y: -8)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: badge)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityValue(badge.map { "\($0)" } ?? "")
    }
}

/// What the big pressed-in headline of a toy game shows.
enum ToyHeadline {
    /// The score, with the best score below.
    case score
    /// A clock, with a caption below (e.g. the difficulty). `time` gives the
    /// game's own "m:ss"; without it the container's round clock is shown.
    case clock(caption: String, time: (() -> String)? = nil)
}

/// The shared toy game screen: pause on the left, the pressed-in headline in
/// the middle, the game's own buttons on the right, then the game.
struct ToyGameStage<Trailing: View, Content: View>: View {
    let palette: ToyPalette
    var headline: ToyHeadline = .score
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content
    @Environment(\.gameHUD) private var hud
    @State private var bump = 0

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                HStack(alignment: .top) {
                    ToyIconButton(symbol: "pause.fill", label: L10n.text("Paused"), ink: palette.ink) { hud.pause() }
                    Spacer()
                    trailing()
                }
                headlineView
                    .padding(.horizontal, 56)
            }
            content()
                .frame(maxHeight: .infinity)
        }
        .foregroundStyle(palette.ink)
        .onChange(of: hud.score) { old, new in
            if new > old { bump += 1 }
        }
    }

    @ViewBuilder
    private var headlineView: some View {
        switch headline {
        case .score:
            ToyPressedScore(score: hud.score, best: hud.best, deboss: palette.deboss,
                            rim: palette.debossRim, ink: palette.ink, bump: bump)
        case .clock(let caption, let time):
            VStack(spacing: 0) {
                // Only the clock redraws each second, not the game below it.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(verbatim: time?() ?? hud.clock())
                        .toyDeboss(palette.deboss, rim: palette.debossRim)
                        .lineLimit(1).minimumScaleFactor(0.4)
                }
                Text(caption)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(palette.ink.opacity(0.7))
            }
            .accessibilityElement(children: .combine)
        }
    }
}

extension ToyGameStage where Trailing == EmptyView {
    init(palette: ToyPalette, headline: ToyHeadline = .score, @ViewBuilder content: @escaping () -> Content) {
        self.init(palette: palette, headline: headline, trailing: { EmptyView() }, content: content)
    }
}
