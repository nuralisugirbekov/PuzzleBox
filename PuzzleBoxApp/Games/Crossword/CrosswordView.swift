import SwiftUI

struct CrosswordView: View {
    @State private var engine = CrosswordEngine()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GameContainerView(gameID: .crossword, engine: engine,
                          resultSummary: L10n.format("Level %d", engine.level),
                          nextLevel: engine.hasNextLevel ? { engine.nextLevel() } : nil) {
            VStack(spacing: 12) {
                hud
                board
                clueBar
                keyboard
            }
        }
        .id(engine.level)
    }

    private var hud: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(1...CrosswordEngine.levelCount, id: \.self) { level in
                    Button(L10n.format("Level %d", level)) { engine.selectLevel(level) }
                }
            } label: {
                Label(L10n.format("Level %d", engine.level), systemImage: "square.grid.3x3.square")
            }
            Text(verbatim: "\(engine.solved.count)/\(engine.clues.count)")
                .monospacedDigit()
                .foregroundStyle(GameTheme.textSecondary)
            Spacer()
            Button { engine.hint() } label: {
                Label(L10n.format("Hint (%d)", engine.hintsLeft), systemImage: "lightbulb.fill")
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(GameTheme.surfaceHigh, in: Capsule())
            }
            .disabled(engine.hintsLeft == 0)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(GameTheme.accent)
    }

    private var board: some View {
        GeometryReader { geo in
            let cell = floor(min(geo.size.width / CGFloat(engine.cols), geo.size.height / CGFloat(engine.rows)))
            let active = Set(engine.activeClue?.cells ?? [])
            let numbers = Dictionary(engine.clues.map { ($0.start, $0.number) }, uniquingKeysWith: { a, _ in a })
            ZStack(alignment: .topLeading) {
                ForEach(Array(engine.solution.keys), id: \.self) { pos in
                    tile(pos, size: cell, active: active.contains(pos), number: numbers[pos])
                        .offset(x: CGFloat(pos.col) * cell, y: CGFloat(pos.row) * cell)
                }
            }
            .frame(width: cell * CGFloat(engine.cols), height: cell * CGFloat(engine.rows), alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(CGFloat(engine.cols) / CGFloat(max(1, engine.rows)), contentMode: .fit)
        .frame(maxHeight: 360)
    }

    private func tile(_ pos: CrosswordCell, size: CGFloat, active: Bool, number: Int?) -> some View {
        let locked = engine.isLocked(pos)
        let selected = engine.selected == pos
        let wrong = engine.wrongClue.flatMap { id in engine.clues.first { $0.id == id } }?.cells.contains(pos) ?? false
        let fill: Color = selected ? GameTheme.accent
            : locked ? Color.green.opacity(0.28)
            : active ? GameTheme.accent.opacity(0.22)
            : GameTheme.surface
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .fill(fill)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                        .strokeBorder(locked ? Color.green.opacity(0.7) : GameTheme.stroke, lineWidth: 1)
                }
            if let number {
                Text(verbatim: "\(number)")
                    .font(.system(size: max(7, size * 0.26), weight: .bold))
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : GameTheme.textSecondary)
                    .padding(.leading, size * 0.08).padding(.top, size * 0.04)
            }
            if let letter = engine.letters[pos] {
                Text(String(letter))
                    .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
                    .foregroundStyle(selected ? Color.white : locked ? Color.green : GameTheme.ink)
                    .frame(width: size, height: size)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: size - 2, height: size - 2)
        .keyframeAnimator(initialValue: CGFloat(0), trigger: wrong ? engine.wrongFlash : 0) { content, x in
            content.offset(x: x)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(reduceMotion ? 0 : 5, duration: 0.05); LinearKeyframe(reduceMotion ? 0 : -5, duration: 0.05)
                LinearKeyframe(reduceMotion ? 0 : 3, duration: 0.05); LinearKeyframe(0, duration: 0.05)
            }
        }
        .animation(.spring(duration: 0.25), value: engine.letters[pos])
        .animation(.spring(duration: 0.35, bounce: 0.4), value: locked)
        .contentShape(Rectangle())
        .onTapGesture { engine.tap(pos) }
    }

    private var clueBar: some View {
        HStack(spacing: 8) {
            Button { engine.stepClue(-1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 44) }
            VStack(alignment: .leading, spacing: 2) {
                if let clue = engine.activeClue {
                    Text(verbatim: "\(clue.number) \(clue.across ? "→" : "↓") · \(clue.answer.count)")
                        .font(.caption.bold()).foregroundStyle(GameTheme.accent)
                    Text(clue.clue)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2).minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.snappy, value: engine.activeClue?.id)
            Button { engine.stepClue(1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 44) }
        }
        .padding(.horizontal, 6)
        .background(GameTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var keyboard: some View {
        VStack(spacing: 6) {
            ForEach(Array(engine.language.keyboardRows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 4) {
                    ForEach(Array(row), id: \.self) { letter in
                        Button { engine.type(letter) } label: {
                            Text(String(letter))
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(GameTheme.surfaceHigh, in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }
                    if index == engine.language.keyboardRows.count - 1 {
                        Button { engine.backspace() } label: {
                            Image(systemName: "delete.left.fill")
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(GameTheme.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.text("Erase"))
                    }
                }
            }
        }
        .foregroundStyle(GameTheme.ink)
    }
}
