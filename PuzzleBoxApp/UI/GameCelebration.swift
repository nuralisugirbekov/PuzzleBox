import SwiftUI

// Shared "juice" for every mini-game: confetti bursts, a counting score,
// floating score deltas. All of it is skipped when Reduce Motion is on.

/// A short confetti shower. Bump `trigger` to fire a new burst.
struct ConfettiView: View {
    let trigger: Int
    var count = 140
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var pieces: [Piece] = []

    private static let duration = 2.8
    private static let colors: [Color] = [.pink, .yellow, .mint, .cyan, .orange, .purple, .green, .red, .blue]

    struct Piece {
        let x: CGFloat
        let delay: Double
        let speed: CGFloat
        let drift: CGFloat
        let sway: CGFloat
        let spin: Double
        let size: CGFloat
        let color: Color
        let round: Bool
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: start == nil)) { context in
            Canvas { canvas, size in
                guard let start else { return }
                let t = context.date.timeIntervalSince(start)
                for piece in pieces {
                    let local = t - piece.delay
                    guard local > 0 else { continue }
                    // Fast launch from above the top edge, then a gentle, swaying fall.
                    let y = -20 + piece.speed * CGFloat(local) + 160 * CGFloat(local * local)
                    guard y < size.height + 20 else { continue }
                    let x = piece.x * size.width + piece.drift * CGFloat(local) + sin(CGFloat(local) * 4 + piece.sway) * 14
                    let fade = max(0, min(1, (Self.duration - t) / 0.6))
                    var layer = canvas
                    layer.opacity = fade
                    layer.translateBy(x: x, y: y)
                    layer.rotate(by: .radians(piece.spin * local))
                    // Flip on one axis so the paper seems to tumble.
                    layer.scaleBy(x: 1, y: abs(cos(CGFloat(local) * 5 + piece.sway)) * 0.8 + 0.2)
                    let rect = CGRect(x: -piece.size / 2, y: -piece.size / 3, width: piece.size, height: piece.size * (piece.round ? 1 : 0.6))
                    layer.fill(piece.round ? Path(ellipseIn: rect) : Path(rect), with: .color(piece.color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in fire() }
    }

    private func fire() {
        guard !reduceMotion else { return }
        pieces = (0..<count).map { _ in
            Piece(x: .random(in: 0...1), delay: .random(in: 0...0.5), speed: .random(in: 60...220),
                  drift: .random(in: -40...40), sway: .random(in: 0...(.pi * 2)), spin: .random(in: -8...8),
                  size: .random(in: 6...11), color: Self.colors.randomElement()!, round: Bool.random())
        }
        let started = Date()
        start = started
        Task {
            try? await Task.sleep(for: .seconds(Self.duration))
            if start == started { start = nil; pieces = [] }
        }
    }
}

/// Text that counts up to its value when animated.
struct CountingText: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View {
        Text(Int(value.rounded()), format: .number)
    }
}

/// A score readout that floats a "+N" above itself and pulses whenever it grows.
struct LiveScoreText: View {
    let value: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var delta = 0
    @State private var bump = 0

    var body: some View {
        Text(value, format: .number)
            .contentTransition(.numericText(value: Double(value)))
            .animation(.snappy, value: value)
            .keyframeAnimator(initialValue: CGFloat(1), trigger: bump) { content, scale in
                content.scaleEffect(scale, anchor: .leading)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(reduceMotion ? 1 : 1.15, duration: 0.12)
                    SpringKeyframe(1, duration: 0.25)
                }
            }
            .overlay(alignment: .topTrailing) {
                if delta > 0 && !reduceMotion {
                    Text(verbatim: "+\(delta)")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.green)
                        .id(bump)
                        .transition(.asymmetric(insertion: .scale(scale: 0.5).combined(with: .opacity),
                                                removal: .move(edge: .top).combined(with: .opacity)))
                        .offset(x: 34, y: -8)
                        .fixedSize()
                }
            }
            .onChange(of: value) { old, new in
                guard new > old else { delta = 0; return }
                withAnimation(.spring(duration: 0.35)) {
                    delta = new - old
                    bump += 1
                }
                let token = bump
                Task {
                    try? await Task.sleep(for: .milliseconds(900))
                    if bump == token { withAnimation(.easeOut(duration: 0.3)) { delta = 0 } }
                }
            }
    }
}

extension View {
    /// Shared dark play-field: a soft vertical gradient with a fine inner rim,
    /// so every canvas game sits on the same polished board.
    func arenaBackground(cornerRadius: CGFloat = 24) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.12, green: 0.13, blue: 0.19), GameTheme.arena],
                                     startPoint: .top, endPoint: .bottom))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.03)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
        }
    }
}
