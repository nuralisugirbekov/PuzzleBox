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
        case .gems:
            return GameTutorial(rules: "Swap two neighbouring gems to line up three or more of a colour. Four in a line leaves a bomb, an L or T shape leaves a cross, five in a line leaves lightning. Gems that fall into new lines score a growing combo. Frozen gems can't be moved: match through them twice, or blast them. The game ends when no move is left, and every power still on the board goes off for a last bonus.", controls: "Swipe a gem towards its neighbour, or tap one gem and then the other. Swap two powers together for a bigger blast. Lightning clears every gem of the colour you swap it with. Tap Hint if you're stuck.")
        case .gemsArcade:
            return GameTutorial(rules: "Every level is a new board: bigger, smaller or oddly shaped, with holes that gems fall past and ice already in place. Collect the crystals within the moves to clear it, and unused moves score a bonus. Run out of moves and you try the level again. Your progress is saved.", controls: "Swipe a gem towards its neighbour, or tap one gem and then the other. Bombs, crosses and lightning work as in the classic game. Above the board you see the level, the moves left and the crystals collected.")
        case .gemsBlitz:
            return GameTutorial(rules: "Collect the crystals before the timer runs out: a crystal is collected when its gem is cleared. Reach the goal to move on to the next level with a fresh minute and a time bonus. Each level needs more crystals and brings more ice. Play solo for a record, or race friends: everyone gets the same boards, and the best score once every clock has run out takes first place.", controls: "Swipe a gem towards its neighbour, or tap one gem and then the other. Bombs, crosses and lightning work as in Gems. If no move is left the board is shuffled. The clock waits while gems are falling.")
        case .crossword:
            return GameTutorial(rules: "Fill the grid with words that match the clues. Correct words turn green and lock in place.", controls: "Tap a cell to choose a word; tap it again to switch between across and down. Type with the keyboard below. Hints reveal one letter.")
        case .asyk:
            return GameTutorial(rules: "Asyk atu is a traditional Kazakh game. Knock the asyks out of the ring with your saqa. Each level has a different arrangement and a limited number of throws. Clear the ring to move on.", controls: "Put your finger on the saqa and swipe toward the asyks, farther for a harder throw. Before throwing, drag along the bottom line to move the saqa.")
        case .togyzkumalak:
            return GameTutorial(rules: "Pick a pit and sow its pebbles counter-clockwise, one per pit. If the last pebble lands on the opponent's side and makes the pit even, you capture it. Exactly 3 makes a tuzdyk, a pit that feeds your kazan from then on (not the 9th pit). Reach more than half the pebbles to win.", controls: "Tap one of your pits (the bottom row). In Quick mode, tap once to preview the move and again to play it. Use Hint for the computer's best suggestion.")
        case .altybakan:
            return GameTutorial(rules: "Pump the swing higher and ring the golden bells hung along both sides of the arc. Each bell is higher than the last. Three mistimed taps end the ride, and the swing slows down if you stop pumping.", controls: "Tap just as the swing passes the glowing spot at the bottom. The brighter centre gives the biggest push.")
        case .kokpar:
            return GameTutorial(rules: "Grab the serke lying on the field, dodge the rival riders and carry it into the kazan at the end. A hit costs a life and makes you drop the serke. Every goal makes the next field longer and harder.", controls: "Swipe left or right to change lanes. You can also tap the left or right side of the field.")
        case .baige:
            return GameTutorial(rules: "Gallop as far as you can. Jump over fences, rocks and ditches, collect coins and grab the golden whip for a burst of speed. A hit costs a life, and three lives are all you get.", controls: "Tap to jump. Hold your finger down for a higher jump, and tap just before landing to jump again at once.")
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
