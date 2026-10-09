import SwiftUI

struct GameTutorial {
    let rules: String
    let controls: String

    static func forGame(_ id: GameID) -> GameTutorial? {
        if let mode = LogicMode(rawValue: id.rawValue) {
            let controls: String
            switch mode {
            case .hashi: controls = "Select two islands in the same row or column. Repeat to add a second bridge or remove it."
            case .kakuro, .futoshiki: controls = "Select an empty cell, then a number below the board. Use × to clear it. Given numbers cannot be changed."
            case .slitherlink, .masyu: controls = "Tap between dots to toggle a line. Every used dot must have exactly two lines; separate loops do not count."
            case .takuzu: controls = "Tap a cell to cycle empty → 0 → 1. Avoid triples horizontally and vertically. Given cells stay fixed."
            case .tents: controls = "Tap an empty cell to place or remove a tent. Each tree needs its own tent on a side, not diagonally."
            case .nurikabe, .hitori: controls = "Tap a cell to shade it; tap again to restore it. Connections use sides, not corners."
            }
            return GameTutorial(rules: mode.hint, controls: controls)
        }
        switch id {
        case .nonogram:
            return GameTutorial(rules: "Numbers show consecutive filled groups in each row and column, in order. Leave at least one empty cell between groups.", controls: "Tap to fill or clear a cell. Switch to × to mark cells that should stay empty.")
        case .numberConnect:
            return GameTutorial(rules: PuzzleMode.numberConnect.hint, controls: "Drag from a numbered endpoint through neighboring cells to its matching number. Start from an endpoint again to redraw that path.")
        case .sudoku:
            return GameTutorial(rules: "Fill 1–9 once in every row, column and 3×3 box.", controls: "Select a cell, then choose a number. Given numbers cannot be changed.")
        case .matchstick:
            return GameTutorial(rules: VisualMode.matchstick.hint, controls: "Select an orange match, then tap a faint empty slot. Only one match may move; the equals sign stays fixed.")
        default: return nil
        }
    }
}

struct GameTutorialView: View {
    let gameID: GameID
    let tutorial: GameTutorial
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Label(gameID.info.title, systemImage: gameID.info.symbol)
                        .font(.title2.bold()).foregroundStyle(gameID.info.tint)
                    VStack(alignment: .leading, spacing: 10) {
                        Label(L10n.text("Rules"), systemImage: "checkmark.circle")
                            .font(.headline)
                        Text(L10n.text(tutorial.rules)).fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Label(L10n.text("Controls"), systemImage: "hand.tap")
                            .font(.headline)
                        Text(L10n.text(tutorial.controls)).fixedSize(horizontal: false, vertical: true)
                    }
                    Button { dismiss() } label: {
                        Text(L10n.text("Got it"))
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                    }.buttonStyle(.borderedProminent)
                }.padding(24)
            }
            .navigationTitle(L10n.text("How to play"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
