# iOS: attention, skill shots and visual puzzles

30 games added to the shared catalog. All use the existing theme, pause/restart/result container, local records and per-game Firebase round events. Names, rules and feedback are available in all eight app languages. New sources are in `PuzzleBoxApp/Games/Playground/`.

## Attention games

`AttentionEngine` and `AttentionView` provide 30 seconds of active play, three lives, a brief feedback pause and speed-based points. The timer pauses during feedback and when the app/game is inactive.

- Odd One Out: one different SF Symbol in a 4×4 field.
- Find the Color: select the ink color of a deliberately conflicting localized color word.
- Biggest Number: six distinct random numbers, select the maximum.
- Missing Number: an arithmetic sequence with four distinct answer choices.
- Which Side?: two dot fields of different sizes; select the larger one.
- Memory Flash: show a random subset for one second, then restore it by tapping; target count grows gradually.
- Find the Pair: twelve visible symbols containing exactly one duplicate pair.
- Ascending: nine shuffled numbers, tap 1 through 9.
- Don’t Tap: clear all nine circles without touching the three triangles.
- Fast Sort: even numbers left, odd numbers right, via swipe or equivalent buttons.

## Skill-shot games

`ToyEngine` and `ToyView` use a normalized 320×460 playfield and subdivided physics steps. Held controls and movement stop on pause/background/exit. Most modes have five attempts with a one-second result pause. Pinball uses a 30-second timer and three balls.

- Basket Shot: swipe direction/length set launch velocity; gravity, rim/backboard collisions, downward hoop crossing.
- Bottle Flip: upward swipe controls flight and spin; a full rotation and near-upright floor contact score a landing.
- Paper Toss: ballistic paper throw, visible horizontal wind and downward bin capture.
- Darts: swipe vector controls a projected landing point; three radial score zones plus bullseye.
- Golf: pull back to launch, friction, wall/obstacle bounces, low-speed hole capture; one shot per attempt.
- Pinball Mini: gravity, round bumpers, side funnels, two held flippers, drain and automatic relaunch until lives run out.
- Plinko: choose a release position, bounce through pegs and land in one of six score bins. Highlighted bin scores 100, others 10.
- Ricochet: one shot, at least one wall bounce required before target capture.
- Rope Cut: two rope constraints, swipe intersection cuts, pendulum motion and gravity; release the candy into the goal.
- Draw Bridge: draw between the marked platform edges, then roll the ball over the line. Clear is available before launch.

These are compact 2D interpretations, not reproductions of commercial assets or full 3D simulations.

## Visual puzzles

`VisualEngine` and `VisualView` provide short generated/starter puzzles, scored by the number of moves. Replay creates another arrangement where applicable.

- Spot the Difference: two symbol pictures with exactly three differences; mark the lower picture.
- Find Hidden Object: locate the single target symbol in a colorful 6×6 field.
- Shadow Match: match a colored vector silhouette to one of four shadows.
- Rotate Puzzle: rotate nine image fragments to match the reference landscape. The image is drawn in SwiftUI Canvas; each tile has an asymmetric visual motif so orientation remains visible.
- Symmetry: complete the right half of a 6×6 grid as a reflection of the left.
- Pattern Match: continue a repeating symbol sequence.
- Tangram: seven actual tangram shapes, a guided square layout, piece selection, quarter turns, dragging and snapping. This starter version uses fixed target slots, not an arbitrary silhouette/packing solver.
- Pixel Puzzle: reproduce one of three small 5×5 images using a five-color palette including background/erase.
- Fold It: single or double folds of a 4×4 paper, with a punch in the folded region; choose its reflected unfolded hole pattern.
- Matchstick Puzzle: single-digit arithmetic equations represented by seven-segment matches. Puzzles are created by moving one match away from a valid equation. Select one occupied and one vacant segment; any resulting valid equation is accepted. Incorrect proposals leave the original layout available for another try.

The visual set is intentionally a small starter collection, not a large authored level campaign.

## Verification status

Source inspection only. Per the user's instruction, no builds, automated tests or simulator/device runs were performed. Compilation, layout on different iPhones and gameplay/physics tuning still require running the app in Xcode.
