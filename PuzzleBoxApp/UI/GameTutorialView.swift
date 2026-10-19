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
        case .durak:
            return GameTutorial(rules: "Get rid of all your cards; the last player still holding cards is the durak. Two to six can play. The attacker leads a card and the defender beats it with a higher card of the same suit or any trump. Then every other player in turn may throw in cards of ranks already on the table. If the defender can't beat a card, they take the whole table.", controls: "Tap a raised card to play it. As defender, tap Take to pick up the table. As an attacker, tap Bito or Pass when you have nothing more to throw in. Play against 1–5 bots, or create a room and invite friends.")
        case .hangman:
            return GameTutorial(rules: "Two to four players guess one hidden word, taking turns. Name a letter: if it's in the word, every copy of it opens and you go again. If not, a part is added to the hanged man and the turn passes. Whoever completes the man is out, and a new one is drawn. Whoever opens the last letter, or is the last one left, wins.", controls: "Tap a letter on the keyboard to name it. Green letters are in the word, grey ones aren't. Words are in the app's language. Play against the bot, or create a room for friends.")
        case .battleship:
            return GameTutorial(rules: "Two players each hide a fleet on a 10×10 board: one four-decker, two three-deckers, three two-deckers and four single boats. Ships can't touch, not even at the corners. Take turns firing at the enemy board. A hit lets you fire again, a miss passes the turn. Once a ship is sunk, the cells around it are marked, since nothing else can be there. Sink the whole enemy fleet to win.", controls: "Shuffle your fleet until you like it, then tap Ready. Tap a cell on the enemy board to fire: a red cross is a hit, a dot is a miss. Your own fleet is shown below. Play against the bot, or create a room for a friend.")
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
