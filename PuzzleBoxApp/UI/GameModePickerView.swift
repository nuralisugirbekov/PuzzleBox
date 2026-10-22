import SwiftUI

/// Shown when a game with several modes is opened (Gems: Classic, Arcade or
/// Blitz). Each mode keeps its own record, shown on its button.
struct GameModePickerView: View {
    let game: GameID
    let play: (GameID) -> Void

    @Environment(StatsStore.self) private var stats

    var body: some View {
        GameChoiceSheet(game: game.modes.first ?? game) {
            ForEach(game.modes, id: \.self) { mode in
                let info = mode.info
                GameChoiceRow(title: mode.modeTitle, detail: info.tagline, symbol: info.symbol, tint: info.tint,
                              prominent: mode == game.modes.first,
                              best: stats.highScore(for: mode)) {
                    AppAnalytics.log("mode_selected", parameters: ["game_id": game.rawValue, "mode": mode.rawValue])
                    play(mode)
                }
            }
        }
    }
}

/// Shown when Minesweeper is opened: the board size is picked before the game.
struct MinesweeperDifficultyAlert: View {
    let play: (MinesweeperDifficulty) -> Void
    let cancel: () -> Void

    var body: some View {
        DifficultyAlert(game: .minesweeper, choices: MinesweeperDifficulty.allCases,
                        prominent: MinesweeperEngine.savedDifficulty,
                        title: \.title,
                        detail: { L10n.format("%d×%d, %d mines", $0.size, $0.size, $0.mines) },
                        play: play, cancel: cancel)
    }
}

/// Shown when Sudoku is opened: the board size and how many digits are given.
struct SudokuDifficultyAlert: View {
    let play: (SudokuDifficulty) -> Void
    let cancel: () -> Void

    var body: some View {
        DifficultyAlert(game: .sudoku, choices: SudokuDifficulty.allCases,
                        prominent: SudokuEngine.savedDifficulty,
                        title: \.title,
                        detail: { L10n.format("%d×%d, %d clues", $0.size, $0.size, $0.clues) },
                        play: play, cancel: cancel)
    }
}

/// Shown when 2048 is opened: the easier, the bigger the board.
struct Game2048DifficultyAlert: View {
    let play: (Game2048Difficulty) -> Void
    let cancel: () -> Void

    var body: some View {
        DifficultyAlert(game: .game2048, choices: Game2048Difficulty.allCases,
                        prominent: Game2048Engine.savedDifficulty,
                        title: \.title,
                        detail: { "\($0.size)×\($0.size)" },
                        play: play, cancel: cancel)
    }
}

/// Shown when Block Blast is opened: how kindly the tray is dealt.
struct BlockBlastDifficultyAlert: View {
    let play: (BlockBlastDifficulty) -> Void
    let cancel: () -> Void

    var body: some View {
        DifficultyAlert(game: .blockBlast, choices: BlockBlastDifficulty.allCases,
                        prominent: BlockBlastEngine.savedDifficulty,
                        title: \.title, play: play, cancel: cancel)
    }
}

/// Figma "Block blast" difficulty alert: the game's artwork and title over
/// one capsule per difficulty, shown over the screen the game was opened
/// from. The difficulty picked last is the prominent one.
struct DifficultyAlert<Choice: Hashable>: View {
    let game: GameID
    let choices: [Choice]
    let prominent: Choice
    /// English key of the choice's name, localized here.
    let title: KeyPath<Choice, String>
    var detail: ((Choice) -> String)? = nil
    let play: (Choice) -> Void
    let cancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: cancel)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(L10n.text("Close"))
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    GamePreviewArt(gameID: game, fade: false)
                        .frame(width: 120, height: 120)
                        .clipShape(.rect(cornerRadius: 20))
                        .accessibilityHidden(true)
                    Text(game.info.title)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                VStack(spacing: 8) {
                    ForEach(choices, id: \.self) { choice in
                        button(for: choice)
                    }
                }
            }
            .padding(14)
            .frame(width: 300)
            .alertSurface(cornerRadius: 34)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity)
    }

    private func button(for choice: Choice) -> some View {
        let isProminent = choice == prominent
        return Button {
            AppAnalytics.log("mode_selected", parameters: ["game_id": game.rawValue, "mode": choice[keyPath: title]])
            play(choice)
        } label: {
            VStack(spacing: 1) {
                Text(L10n.text(choice[keyPath: title]))
                    .font(.headline)
                if let detail {
                    Text(detail(choice))
                        .font(.subheadline)
                        .opacity(0.75)
                }
            }
            .foregroundStyle(isProminent ? Color.white : Color.primary)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(isProminent ? AnyShapeStyle(GameTheme.accent)
                                    : AnyShapeStyle(Color(.tertiarySystemFill)),
                        in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The sheet shared by the pickers: the game's artwork and title over a list of choices.
struct GameChoiceSheet<Choices: View>: View {
    let game: GameID
    @ViewBuilder let choices: () -> Choices

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    GamePreviewArt(gameID: game, fade: false)
                        .frame(width: 72, height: 72)
                        .clipShape(.rect(cornerRadius: 20))
                        .padding(.bottom, 8)
                    choices()
                }
                .padding(24)
            }
            .navigationTitle(game.info.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("Close")) { dismiss() }
                }
            }
        }
        // Tall enough for every choice without dragging the sheet up.
        .presentationDetents([.fraction(0.75), .large])
    }
}

/// One choice in a picker sheet; the prominent one is the suggested pick.
struct GameChoiceRow: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    var prominent = false
    var best = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(prominent ? Color.white : tint)
                    .frame(width: 44, height: 44)
                    .background(prominent ? AnyShapeStyle(Color.white.opacity(0.2)) : AnyShapeStyle(tint.opacity(0.15)),
                                in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .opacity(0.8)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if best > 0 {
                        Label(L10n.format("Best: %d", best), systemImage: "trophy.fill")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .opacity(0.8)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).opacity(0.6)
            }
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(prominent ? AnyShapeStyle(GameTheme.accent) : AnyShapeStyle(Color(.tertiarySystemFill)),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
