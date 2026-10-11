import SwiftUI
import Observation

// Small shared effects for the classic puzzle and card games:
// floating "+N" score popups and the felt table used by the card games.

struct ClassicFXPopup: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let color: Color
    /// Position inside the layer in unit coordinates (0…1).
    let anchor: UnitPoint
    var large = false
}

/// Engines own one feed and push popups into it; views render it with `ClassicFXPopupLayer`.
@MainActor
@Observable
final class ClassicFXPopupFeed {
    private(set) var items: [ClassicFXPopup] = []

    func show(_ text: String, color: Color = .orange, at anchor: UnitPoint = .center, large: Bool = false) {
        let popup = ClassicFXPopup(text: text, color: color, anchor: anchor, large: large)
        items.append(popup)
        if items.count > 6 { items.removeFirst(items.count - 6) }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1100))
            self?.items.removeAll { $0.id == popup.id }
        }
    }

    func clear() { items.removeAll() }
}

struct ClassicFXPopupLayer: View {
    let feed: ClassicFXPopupFeed

    var body: some View {
        GeometryReader { geo in
            ForEach(feed.items) { popup in
                ClassicFXPopupView(popup: popup)
                    .position(x: geo.size.width * popup.anchor.x, y: geo.size.height * popup.anchor.y)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ClassicFXPopupView: View {
    let popup: ClassicFXPopup
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Values {
        var rise: CGFloat = 0
        var scale: CGFloat = 0.6
        var opacity: Double = 0
    }

    var body: some View {
        Text(verbatim: popup.text)
            .font(.system(popup.large ? .title : .title3, design: .rounded).weight(.heavy))
            .foregroundStyle(popup.color)
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .fixedSize()
            .keyframeAnimator(initialValue: Values()) { content, value in
                content
                    .scaleEffect(value.scale)
                    .offset(y: value.rise)
                    .opacity(value.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    SpringKeyframe(reduceMotion ? 1 : 1.15, duration: 0.2)
                    CubicKeyframe(1, duration: 0.2)
                }
                KeyframeTrack(\.rise) {
                    CubicKeyframe(reduceMotion ? 0 : -46, duration: 1.0)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.12)
                    LinearKeyframe(1, duration: 0.55)
                    LinearKeyframe(0, duration: 0.33)
                }
            }
    }
}

/// Green card-table background so empty pile outlines stay visible in light mode.
struct ClassicFeltTable: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                RadialGradient(colors: [Color(red: 0.13, green: 0.47, blue: 0.29),
                                        Color(red: 0.06, green: 0.29, blue: 0.18)],
                               center: .top, startRadius: 20, endRadius: 520)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.25), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}

/// Small capsule button used on the felt table (hint, auto-complete…).
struct ClassicTableButton: View {
    let title: String
    let symbol: String
    var prominent = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(prominent ? Color.white : (isEnabled ? GameTheme.accent : GameTheme.textSecondary))
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(prominent ? AnyShapeStyle(GameTheme.accent.gradient) : AnyShapeStyle(GameTheme.surface),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
