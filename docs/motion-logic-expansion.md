# Motion and logic expansion (iOS)

19 new games: 10 arcade games and 9 logic puzzles. Numberlink reuses the existing Number Connect engine and `numberConnect` identifier, preserving its records. Its menu title now says Numberlink; search also recognizes the previous localized title.

## Integration

- `Games/Expansion/MotionEngine.swift` and `MotionView.swift`: ten real-time modes, separate mechanics and controls.
- `Games/Expansion/LogicEngine.swift` and `LogicView.swift`: puzzle state, generated starter boards, rule-based completion, undo, number entry, line/bridge controls and explicit solution checking.
- Shared `GameContainerView` supplies pause/restart/results, score records and analytics events using each game's stable ID.
- Titles, instructions and feedback are localized for all eight supported languages.
- No Android changes, new dependencies, downloaded art or copied puzzle layouts.

## Arcade controls and scoring

- Slope: top-down rolling ball, horizontal dragging, scrolling holes; distance score.
- Keep It Up: tap near the ball to give an upward impulse. Gravity, wall bounces, loss below the floor; 10 points per successful tap with a short cooldown.
- Wall Jump: automatic crossings between walls. Tap switches between two heights to avoid the spike cluster on the approaching wall; 10 points per crossing.
- Circle Pong: drag around the center to rotate the edge paddle. Ball reflections accelerate up to a cap; 10 points per return, loss on a missed return.
- Space Dodge: one-finger ship movement and incoming asteroids; distance score.
- Lane Switch: one lane per horizontal swipe across three lanes, with one blocked lane per incoming row; distance score.
- Gravity Flip: tap reverses vertical acceleration between floor and ceiling. Obstacles approach along either surface; 10 points per obstacle passed.
- Cannon Shot: timing a shot from an oscillating cannon into the next one. Each successful capture shifts the next cannon into the launch position; 25 points per capture.
- Endless Climb: automatic platform bounces, horizontal dragging and vertical camera scrolling; height score.
- Drift: hold to steer clockwise, release for straight movement on a closed stadium track. Camera follows the car; forward track progress determines score. Leaving the road ends the round.

These are minimal 2D versions. Timesteps are capped and subdivided. Movement stops while paused, backgrounded or off-screen, and held input is cleared on lifecycle changes.

## Puzzle rules and starter boards

All completions validate the current board against rules, not equality with a hidden answer. Generation starts from a valid construction. Uniqueness is not asserted; alternative rule-valid answers are accepted.

- Hashi: nine islands with randomized degrees derived from a connected bridge tree. Aligned island taps cycle zero/single/double bridges. Intervening islands and crossings are blocked. Completion requires all degrees and a connected graph.
- Kakuro: compact crossed runs, each with a displayed arrow sum. Input 1–9 without repetition within a run; every run is checked. Sums vary with the generated digit permutation.
- Nurikabe: starter pattern of white pairs with randomized clue locations and rotation. Completion verifies numbered island sizes, exactly one clue per island, connected black sea and absence of black 2×2 squares.
- Slitherlink: 4×4 clue grid derived from boundaries of three small connected shapes and their rotations. Completion verifies surrounding edge counts and exactly one nonbranching loop.
- Futoshiki: randomized 4×4 Latin square, five givens and ten inequalities. Completion checks range, row/column uniqueness and all inequalities.
- Hitori: 4×4 Latin base with introduced duplicates, digit permutation and rotation. Completion checks remaining numbers, separation of black cells and connectivity of white cells.
- Takuzu: 4×4 starter board with six givens, rotations and binary inversion. Completion checks equal counts, forbidden triples and distinct rows/columns.
- Tents: 6×6 starter board and rotations. Completion checks row/column totals, no touching tents (including diagonals), and a one-to-one orthogonal matching between trees and tents.
- Masyu: 5×5 introductory layout and rotations. Completion requires one loop through every pearl; white pearls are straight with an adjacent turn, black pearls turn with straight adjacent cells on both sides.

Nurikabe, Tents and Masyu currently have small starter constructions rather than a large level campaign. The visual rules/control text is included in each game.

Rules referenced from the original publisher, without copying example grids: [Hashi](https://www.nikoli.co.jp/en/puzzles/hashiwokakero/), [Kakuro](https://www.nikoli.co.jp/en/puzzles/kakuro/), [Nurikabe](https://www.nikoli.co.jp/en/puzzles/nurikabe/), [Slitherlink](https://www.nikoli.com/en/puzzles/slitherlink/), [Hitori](https://www.nikoli.co.jp/en/puzzles/hitori/), [Masyu](https://www.nikoli.co.jp/en/puzzles/masyu/).

## Validation status

Source inspection only. At the user's request no builds, tests or simulator runs were performed. Compilation, device layout, gesture feel and gameplay balance remain to be verified by running the app in Xcode.
