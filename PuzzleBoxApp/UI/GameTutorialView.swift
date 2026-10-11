import SwiftUI

struct GameTutorial {
    let rules: String
    let controls: String

    static func forGame(_ id: GameID) -> GameTutorial? {
        switch id {
        case .arrowEscape:
            return GameTutorial(rules: "Clear every arrow from the board. An arrow can leave only when no other arrow blocks the straight line ahead of its tip.", controls: "Tap any part of an arrow to send it out. A blocked arrow turns red and costs a life. You have 3 lives per level, so look before you tap.")
        case .arrowMaze:
            return GameTutorial(rules: "The rocket flies forward on its own and speeds up with every star. Collect all the stars, then fly into the green portal. Touching the rocks ends the round.", controls: "Tap the left half of the maze to turn left, or the right half to turn right. Each turn is 90°. Turn near the center of a junction. You can also use the buttons below.")
        case .numberConnect:
            return GameTutorial(rules: PuzzleMode.numberConnect.hint, controls: "Drag from a numbered endpoint through neighboring cells to its matching number. Start from an endpoint again to redraw that path.")

        case .nonogram:
            return GameTutorial(rules: "Numbers show consecutive filled groups in each row and column, in order. Leave at least one empty cell between groups.", controls: "Tap to fill or clear a cell. Switch to × to mark cells that should stay empty.")

        case .sudoku:
            return GameTutorial(rules: "Fill 1–9 once in every row, column and 3×3 box.", controls: "Select a cell, then choose a number. Given numbers cannot be changed.")

        case .matchstick:
            return GameTutorial(rules: VisualMode.matchstick.hint, controls: "Select a match, then tap a faint empty slot. The board shows how many matches you must move; the equals sign stays fixed. Use the reset button to start over.")
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
