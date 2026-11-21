# Oina: first-hand per-game observations (iPhone 17e simulator, iOS 26, light and dark, 2026-11-14)

These are my own observations from screenshots of every visible game in its opening state, not web research. All games use the shared skeleton described in oina_component_audit.md. Screen height is 844 pt; the board usually starts around y = 160–200 pt.

## Problems seen in almost every game
- **Unreadable headline:** the big debossed headline is nearly invisible (light peach "0" on peach, "00:00" on lavender). Players cannot read the score or clock at a glance. In card and duel games the headline is a clock that means little ("00:01 vs Bot").
- **Same top band everywhere:** pause, headline, then "Your best · n", then a chip row. That is about 150–200 pt of chrome before the board.
- **Dead space:** a large empty area under the board in many games (2048, Water Sort, Merge Fruit, Spider, FreeCell, Durak, Matchsticks, Chess, Laser, Unblock, Light Out). The board is often not vertically balanced, and controls are not at the bottom where the thumb is.
- **Tool buttons at the top:** game tools (undo, hint, extra tube, flag mode, reset, lives) are mostly top-right, the hardest place to reach one-handed. A few games (Solitaire hint/undo, Sudoku number pad, Snake d-pad, Unblock arrows) put controls at the bottom, which is better but inconsistent.
- **Blocking start card:** seven arcade games (Helix, Flappy, Road Hop, Stack, Whack-a-Mole, Red/Green, Perfect Timing, Circle Pong, Mini Golf) open with the same "Tap to start" toy card covering the middle of the board. It hides the very thing the player should look at, and only some versions show a one-line rule.
- **Text-only onboarding:** onboarding is a text sheet (system styling, blue button) plus a faint hint line under the board that disappears after the first move.
- **Resume window on open:** many games open on the "Continue previous game?" window, and some open on the pause window under the tutorial sheet. The very first impression is a modal, not the game.
- **Status chips look like buttons:** they have the same raised look whether or not they are tappable (the level chip is a menu; "Moves: 0" and stars are not).

## Per game
### 2048 (sand)
- The board is centred with about 150 pt empty below it.
- "Best tile: 2" and the swipe hint are at the bottom in tiny grey text.
- The undo button has a "•••" under it that is unexplained (probably undo charges).
- The headline is the score.

### Block Blast (mint)
- Opens on the Resume window.
- The piece tray is under the board (good).
- The score is debossed and hard to read; the score is the main motivator here.

### Stack (sky)
- A full-screen 3D tower with the start card over it.
- The headline is the score with best under it. Fine for a score-chaser, but the readability problem remains.

### Water Sort (pink)
- Five small tubes in two rows, about 40 % of the width, with lots of empty space.
- Level and moves chips; "+" (extra tube) at the top right.
- Tubes could be much larger; the controls are not at the bottom.

### Minesweeper (green)
- Mine-count chip (flag 10).
- The mode toggle "Open cells" is a chip-like button at the top right.
- The clock headline says "00:00 Easy".
- The board is big (good).
- The hint about long-press is at the bottom in faint text.
- The flag/open mode toggle should be near the thumb.

### Sudoku (lavender)
- Clock and difficulty headline.
- Board, then the number pad with remaining counts, then Erase, Notes and Hint (with badge) at the bottom. This layout is closest to the reference games (Good Sudoku).
- The numbers on the pad are small for 6 columns.

### Gems (lilac) / Gems Arcade / Gems Blitz
- Classic: a combo chip and a Hint chip above the board.
- Arcade: Level chip, moves 15 and crystals 0/10, opened under the tutorial sheet plus the pause window.
- Blitz: a progress bar with the time remaining (59).
- The level goal (crystals) is a small chip and not the hero, unlike Royal Match and Candy Crush where the goal panel is the HUD.

### Helix Drop
- A full-height 3D tower with the start card over the middle of the tower.

### Knife Spin
- Opened on the Resume window.
- A "Level 2" chip next to the score at the top right.
- The knife count is not visible in the opening state.

### Flappy Flight (sky)
- Score headline, clouds, start card.
- Since it is a pure score-chaser, the HUD could be just the number.

### Road Hop
- Score in the top band over the road scene; the start card covers the road.

### Snake (yellow)
- Level chip; the board is a small square (about 260 pt).
- A d-pad of four arrow buttons at the bottom, plus swipe.
- The board could be larger; the arrows are a separate cluster that does not look connected to the board.

### Merge Fruit (mint)
- "Next fruit" chip on the left; the crown and cherry (next-but-one?) chip on the right is unclear.
- The tall jar takes about 65 % of the height (good).

### Solitaire (Klondike, sage)
- The stock and foundations are tiny at the top; the cards are small.
- Hint and undo are at the bottom centre, about 1/3 of the screen apart, which leaves a large gap.
- The score headline is not meaningful for solitaire. Time and moves are the classic metrics.

### Spider (lilac)
- The "1 suit / 2 suits" segmented toggle and "Deal (5)" are in the chip row.
- Ten columns of very small cards fill only the top third; the bottom half is empty with undo alone.
- The 0/8 runs counter is top right.

### FreeCell (sky)
- The cards are very small; empty space below; undo is alone at the bottom.

### Durak vs bot (rose/teal)
- The clock headline "00:01 vs Bot" carries no game information.
- The bot's hand is at the top.
- The trump and deck are on the left with an overlapping small card; the trump is barely legible.
- The table card is in the middle.
- The action "Take" is a teal capsule above the player's fan of cards at the bottom (good).

### Hangman (slate)
- The clock headline is meaningless.
- Player chips (You / Bot) at the top; the gallows is small.
- The word slots and dot beads for mistakes.
- The full Cyrillic keyboard at the bottom (good).
- The mistakes bead row duplicates what the gallows shows.

### Battleship (sand)
- Placement phase: "Place your fleet" heading plus a long paragraph of rules on screen, the board, then Shuffle and Ready at the bottom (good).
- The clock headline is meaningless.

### Lights Out (lavender)
- 3×3 board; clock, "Moves: 0", level and stars chips, undo at the top right.
- The board is OK, with empty space below.

### 15 Puzzle (peach)
- 3×3 board; same skeleton as Lights Out.

### Flood Fill (green)
- The colour buttons at the bottom are good, near the thumb.
- The "Moves left: 16" chip is the key goal but is small and at the top right.

### Number Connect (pink)
- 5×5 board; empty space below.

### Unblock (yellow/grey)
- The board plus four arrow buttons that look disabled (grey socket style).
- Unclear whether the arrows are needed since drag exists.
- The exit is a thin green mark.

### Laser (sky)
- The board; the start arrow and goal star are small.

### Whack-a-Mole (green)
- Chips: 0:30 clock and five hearts. The start card is over the field.

### Red Light Green Light (peach)
- Timer chip, flag 0/30, hearts; a vertical traffic light and track. The start card is over the light.

### Perfect Timing (yellow)
- Hearts; a bar with a zone. The start card covers the bar. A big "0" is shown inside the field as well as in the headline (duplicate score).

### Circle Pong (teal)
- Score only. The ring court is large (good). The start card covers the ring.

### Maze Paint, Arrow Escape, Mini Golf, Matchsticks, Simon, Chess
See the earlier session screenshots:
- **Same skeleton:** all have the same layout.
- **Simon:** the Start button sits below the console.
- **Chess:** a separate setup screen to choose the duration.
- **Arrow Escape:** a 100-level dropdown, lives as hearts, zoom buttons in the old glass style.

## Flows (all games)
- **Pause:** the same window: Resume, Restart, How to play, Home.
- **Result:** the same toy card for win and lose: glyph, title, score in a well, best, Play again, Home, and a 40 pt ✕.
- **Next level:** level games auto-advance 1.7 s after a win, with no stars or result.
- **Tutorial:** a text sheet on the first open.
