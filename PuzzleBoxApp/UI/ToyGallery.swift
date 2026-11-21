#if DEBUG
import SwiftUI

/// TEMP: the toy components side by side in each look, for choosing the
/// rebuilt button style. Opened with `-debugGallery 1`. Remove before shipping.
struct ToyGallery: View {
    var palette: ToyPalette = ToyPuzzles.fifteen
    var pressed = false

    var body: some View {
        ZStack {
            palette.backdrop.ignoresSafeArea()
            if let kind = UserDefaults.standard.string(forKey: "debugResult") {
                // TEMP: the result card variants.
                GameOverOverlay(won: kind != "lose" && kind != "scorelose",
                                score: 1240, highScore: 980,
                                isNewHighScore: kind == "record",
                                playAgain: {},
                                next: kind == "win" ? {} : nil,
                                isLevel: kind == "win" || kind == "lose",
                                home: {}, close: {})
                    .environment(\.toyStyle, ToyStyle(card: palette.card, accent: palette.accent, ink: palette.ink, tray: palette.tray, haze: palette.backdropTop))
            } else if UserDefaults.standard.bool(forKey: "debugHeadlines") {
                headlines.padding(.horizontal, 16)
            } else {
                column.padding(.horizontal, 40)
            }
        }
    }

    /// TEMP: the score headline options, each in a mock top band.
    private var headlines: some View {
        VStack(spacing: 22) {
            band("Сейчас") {
                Text("128").toyDeboss(palette.deboss, rim: palette.debossRim)
            }
            band("1 · крупно, цвет текста") {
                Text("128")
                    .font(.system(size: 56, weight: .black, design: .rounded)).monospacedDigit()
                    .foregroundStyle(palette.ink)
                    .shadow(color: .white.opacity(0.6), radius: 0, y: 1.5)
            }
            band("2 · в табличке") {
                Text("128")
                    .font(.system(size: 34, weight: .black, design: .rounded)).monospacedDigit()
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, 22).frame(minHeight: 52)
                    .background {
                        Capsule().fill(palette.card.toyShade(-0.03)
                            .shadow(.inner(color: .black.opacity(0.22), radius: 3, y: 2)))
                            .overlay { Capsule().strokeBorder(LinearGradient(colors: [.clear, .white.opacity(0.5)], startPoint: .top, endPoint: .bottom), lineWidth: 1) }
                    }
            }
            band("3 · компактно, рекорд рядом") {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("128")
                        .font(.system(size: 40, weight: .black, design: .rounded)).monospacedDigit()
                        .foregroundStyle(palette.ink)
                    Label("326", systemImage: "crown.fill")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(palette.ink.opacity(0.75))
                }
            }
        }
    }

    private func band<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(.caption, design: .rounded).weight(.bold)).foregroundStyle(palette.ink.opacity(0.6))
            HStack(alignment: .top) {
                ToyIconButton(symbol: "pause.fill", label: "Pause", ink: palette.ink) {}
                Spacer()
                content()
                Spacer()
                ToyIconButton(symbol: "arrow.uturn.backward", label: "Undo", ink: palette.ink) {}
            }
        }
    }

    private var column: some View {
        VStack(spacing: 18) {
            ToyCapsuleButton(title: "Дальше", symbol: "play.fill", color: palette.accent, ink: .white) {}
            ToyCapsuleButton(title: "Домой", symbol: "house.fill", color: palette.card, ink: palette.ink) {}
            HStack(spacing: 10) {
                ToyIconButton(symbol: "pause.fill", label: "Pause", ink: palette.ink) {}
                ToyIconButton(symbol: "arrow.uturn.backward", label: "Undo", ink: palette.ink) {}
            }
            ToyIconButton(symbol: "lightbulb.fill", label: "Hint", ink: palette.ink) {}
                .disabled(true)
            HStack {
                ToyMenuChip(color: palette.card, ink: palette.ink) { Text("Уровень 1") }
                Spacer()
                ToyChip(color: palette.card) { Label("Ходов: 3", systemImage: "arrow.left.arrow.right").foregroundStyle(palette.ink) }
            }
            // A static pressed piece, to see the sunk state.
            Text("Нажата").font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.bottom, 4)
                .offset(y: 4)
                .background { ToyBlock(color: palette.accent, shape: Capsule(), lip: 4, pressed: true) }
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    GridRow {
                        ForEach(0..<3, id: \.self) { c in
                            if c == 1 {
                                Text("8").font(.system(size: 22, weight: .heavy, design: .rounded))
                                    .foregroundStyle(palette.ink)
                                    .frame(width: 30, height: 30)
                                    .padding(.bottom, 3)
                                    .background { ToyBlock(color: palette.card, shape: RoundedRectangle(cornerRadius: 9, style: .continuous), lip: 3) }
                            } else {
                                ToySocket(color: palette.socket, shape: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    .frame(width: 30, height: 33)
                            }
                        }
                    }
                }
            }
            .toyTray(palette.tray, cornerRadius: 18, padding: 8)
        }
        .frame(maxWidth: .infinity)
    }
}
#endif
