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

/// A raised piece: one solid object whose darker lip is the side wall under
/// the face, in any shape.
///
/// Built after the design review (see reports/UI и юзабилити игр Oina.md):
/// the lip is the face's own hue, darker, and shades towards the ends like a
/// rounded wall; the highlight is an inner shadow inside the face, not a
/// ring around it; one tight contact shadow tinted with the piece's colour.
/// Pressing sinks the face fully into the lip while the lip stays put.
struct ToyBlock<S: InsettableShape>: View {
    let color: Color
    var shape: S
    /// Height of the side wall under the face, in points.
    var lip: CGFloat = 4
    var pressed = false
    /// Off for pieces that sit on a busy surface and shouldn't cast far.
    var castsShadow = true

    var body: some View {
        let sink = pressed ? lip : 0
        let wall = color.toyShade(-0.18)
        ZStack(alignment: .top) {
            // The wall: same hue, darker, rounding away from the light at both
            // ends. Drawn as one silhouette from the face's top to the lip's bottom.
            SilhouetteShape(shape: shape, top: sink, lip: lip)
                .fill(wall)
                .overlay {
                    shape.fill(LinearGradient(stops: [
                        .init(color: .black.opacity(0.16), location: 0),
                        .init(color: .clear, location: 0.1),
                        .init(color: .clear, location: 0.9),
                        .init(color: .black.opacity(0.16), location: 1),
                    ], startPoint: .leading, endPoint: .trailing))
                    .mask { SilhouetteShape(shape: shape, top: sink, lip: lip) }
                }
            // The face, lit from above, with a soft highlight just inside its top edge.
            shape.fill(LinearGradient(colors: [color.toyShade(0.05), color],
                                      startPoint: .top, endPoint: .bottom)
                .shadow(.inner(color: .white.opacity(0.5), radius: 0.5, y: 1.5))
                .shadow(.inner(color: wall.opacity(0.35), radius: 1, y: -1)))
                .offset(y: sink)
        }
        .padding(.bottom, lip)
        .compositingGroup()
        .shadow(color: color.toyShade(-0.45).opacity(castsShadow ? (pressed ? 0.18 : 0.28) : 0),
                radius: pressed ? 1 : 2, y: pressed ? 1 : 2)
    }
}

/// `shape` at `top` and a copy `lip` lower, joined into one outline.
private struct SilhouetteShape<S: Shape>: Shape {
    let shape: S
    /// Where the face's top is now (it moves down while pressed).
    let top: CGFloat
    let lip: CGFloat

    func path(in rect: CGRect) -> Path {
        let band = max(0, lip - top)
        return shape.path(in: rect.offsetBy(dx: 0, dy: top))
            .union(shape.path(in: rect.offsetBy(dx: 0, dy: lip)))
            .union(Path(CGRect(x: rect.minX, y: rect.midY + top, width: rect.width, height: band)))
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

/// Buttons whose face sinks into its lip while held, with a light tap.
/// A disabled button lies flat and loses its colour; under Reduce Motion the
/// face darkens instead of moving.
struct ToyPressStyle: ButtonStyle {
    var color: Color
    var lip: CGFloat = 4
    var cornerRadius: CGFloat? = nil

    func makeBody(configuration: Configuration) -> some View {
        ToyPressBody(configuration: configuration, color: color, lip: lip, cornerRadius: cornerRadius)
    }
}

private struct ToyPressBody: View {
    let configuration: ButtonStyleConfiguration
    let color: Color
    let lip: CGFloat
    let cornerRadius: CGFloat?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pressed = configuration.isPressed && isEnabled
        let moves = pressed && !reduceMotion
        let face = isEnabled ? color : color.toyShade(-0.04)
        configuration.label
            .padding(.bottom, lip)
            .offset(y: moves ? lip : 0)
            .opacity(isEnabled ? 1 : 0.55)
            .background {
                Group {
                    if let cornerRadius {
                        ToyBlock(color: face, shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                                 lip: lip, pressed: moves, castsShadow: isEnabled)
                    } else {
                        ToyBlock(color: face, shape: Capsule(), lip: lip, pressed: moves, castsShadow: isEnabled)
                    }
                }
                .saturation(isEnabled ? 1 : 0.25)
                .brightness(pressed && reduceMotion ? -0.06 : 0)
            }
            .animation(configuration.isPressed ? .easeOut(duration: 0.05)
                                               : .spring(response: 0.3, dampingFraction: 0.88),
                       value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed && isEnabled { Haptics.soft() }
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

/// The score in the game's ink, with the best score beside it on the same
/// line. Readable first: ink on the backdrop, and it grows with Dynamic Type.
/// (`deboss` and `rim` are kept for callers; the pressed-in look was dropped
/// after the design review because it was nearly invisible.)
struct ToyPressedScore: View {
    let score: Int
    let best: Int
    var deboss: Color = .clear
    var rim: Color = .clear
    var ink: Color
    /// Changing it plays a little bump, e.g. when points land.
    var bump = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(score, format: .number)
                .toyHeadlineNumber(ink)
                .contentTransition(.numericText())
                .animation(.snappy, value: score)
                .keyframeAnimator(initialValue: CGFloat(1), trigger: bump) { content, scale in
                    content.scaleEffect(scale)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(reduceMotion ? 1 : 1.1, duration: 0.08)
                        SpringKeyframe(1, duration: 0.25)
                    }
                }
            if best > 0 {
                Label { Text(best, format: .number).monospacedDigit() } icon: { Image(systemName: "crown.fill") }
                    .toyHeadlineCaption(ink)
                    .accessibilityLabel(L10n.text("Your best") + " " + "\(best)")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The big number of a toy game's headline (score, clock): the game's ink,
/// 40 pt rounded black at the default text size, growing with Dynamic Type
/// up to a limit so it never pushes the board off the screen.
private struct ToyHeadlineNumber: ViewModifier {
    let ink: Color
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 40

    func body(content: Content) -> some View {
        content
            .font(.system(size: min(size, 60), weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(ink)
            .lineLimit(1).minimumScaleFactor(0.6)
    }
}

extension View {
    func toyHeadlineNumber(_ ink: Color) -> some View { modifier(ToyHeadlineNumber(ink: ink)) }

    /// The small text beside the headline number (best score, moves, difficulty).
    func toyHeadlineCaption(_ ink: Color) -> some View {
        self.font(.system(.subheadline, design: .rounded).weight(.bold))
            .foregroundStyle(ink.opacity(0.75))
            .lineLimit(1)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
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

/// A read-only status value (moves, flags, combo) pressed into the backdrop,
/// so it never looks like something to tap. Tappable chips are `ToyMenuChip`.
struct ToyChip<Content: View>: View {
    var color: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .background {
                Capsule()
                    .fill(color.toyShade(-0.03)
                        .shadow(.inner(color: .black.opacity(0.2), radius: 2, y: 1.5)))
                    .overlay {
                        Capsule().strokeBorder(LinearGradient(colors: [.clear, .white.opacity(0.45)],
                                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    }
            }
    }
}

/// A raised chip that opens a menu or switches a mode (level, difficulty):
/// a toy button with a chevron and a 44 pt tap area.
struct ToyMenuChip<Content: View>: View {
    var color: Color
    var ink: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 5) {
            content()
            Image(systemName: "chevron.down").font(.caption2.weight(.heavy)).opacity(0.6)
        }
        .font(.system(.subheadline, design: .rounded).weight(.bold))
        .foregroundStyle(ink)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .padding(.bottom, 3)
        .background { ToyBlock(color: color, shape: Capsule(), lip: 3) }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
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
                .lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(ink)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 44)
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
            ToyPressedScore(score: hud.score, best: hud.best, ink: palette.ink, bump: bump)
        case .clock(let caption, let time):
            // The clock with its caption beside it; stacked when they don't fit.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 10) { clock(time); clockCaption(caption) }
                VStack(spacing: 0) { clock(time); clockCaption(caption) }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

extension ToyGameStage {
    /// Only the clock redraws each second, not the game below it.
    fileprivate func clock(_ time: (() -> String)?) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(verbatim: time?() ?? hud.clock())
                .toyHeadlineNumber(palette.ink)
        }
        .fixedSize()
    }

    fileprivate func clockCaption(_ caption: String) -> some View {
        Text(caption).toyHeadlineCaption(palette.ink).fixedSize()
    }
}

extension ToyGameStage where Trailing == EmptyView {
    init(palette: ToyPalette, headline: ToyHeadline = .score, @ViewBuilder content: @escaping () -> Content) {
        self.init(palette: palette, headline: headline, trailing: { EmptyView() }, content: content)
    }
}
