# Arrow Escape — grid puzzle

The new Arrow Escape is a separate logic game. The earlier continuously moving SpriteKit game is now **Arrow Maze**; its implementation is in `Games/ArrowMaze` and its specification is `arrow-maze.md`. Its persisted raw game ID remains `arrowEscape`, preserving scores, favorites, recent history and tutorial state. The new puzzle uses raw ID `arrowEscapePuzzle` and its own statistics/tutorial.

## Rules and presentation

The entire rectangular board is partitioned into nonoverlapping, orthogonally connected arrow paths. Tap any occupied cell of an arrow. It can leave only when the straight ray from its head to the board edge contains no other arrow. A blocked selection is highlighted red and counts as a mistake; it does not lose a life or end the level. Freed arrows unwind tail-first along their original path while the head travels straight out. Only one departure is active at once, keeping occupancy and animations consistent. Clear all arrows to win.

There are 100 original deterministic generated levels, progressing from 15×20 to 44×58 cells. These are not copies of the referenced website's layouts; arrow counts vary with the generated partition and are not fixed to 47/241. Long paths bend frequently; isolated residual cells become short arrows. The level menu exposes all 100 levels. Scroll in two dimensions and use zoom controls for large boards. The UI uses the app's adaptive theme, rounded board, shared pause/result controls and eight languages.

## Solvability construction

Start with every cell marked remaining. Choose a head at a row or column extremum of remaining cells, facing outward along an empty ray. Grow its body backwards through adjacent remaining cells, then remove those cells from the construction workspace. Prefer candidates with room for a multi-cell body. Repeat until all cells are assigned. At every nonempty step an extremal cell exists; hence construction terminates. Its removal order is a solution: cells obstructing a head's exit ray can only belong to arrows removed earlier in that order. Store this order in `solution` for validation.

Integer seeded randomness and explicitly ordered candidate lists make a given level stable across launches; Set iteration never selects a random candidate. Generation scans row/column extrema instead of casting rays from every remaining cell. The selected board is retained across restart; selecting a different level generates its board.

## Implementation

- `ArrowEscapePuzzle.swift`: cell/direction/path models, seeded generation and ray-based legal-move checks.
- `ArrowEscapePuzzleEngine.swift`: observable game state, occupancy dictionary, serialized departure, blocked feedback, per-attempt score and lifecycle guards.
- `ArrowEscapePuzzleView.swift`: SwiftUI Canvas, path clipping/interpolation, scroll and zoom, level selection and a cancellable animation task that runs only during departures.

Arrows stay occupied until the departure finishes. Animation progresses only while the app is active and the engine is playing. Restart or level change increments a task token and cancels old animation work. Reduced Motion fades the selected arrow instead of unwinding it. No physics engine is necessary for a discrete grid puzzle.

Each removed arrow gives 10 points. Completing a board adds `max(0, 500 − 20 × mistakes)`. Mistakes never reduce the already-earned score. Best scores and game-round events use the shared container; progress within an unfinished board is not persisted across app termination.

## Validation status

Added unexecuted Swift Testing cases for complete cell coverage, nonoverlap, path connectivity, head direction, all 100 solution orders, distant blockers and pause/restart cancellation. No app build, simulator run or test execution was performed, as requested. Device validation of scrolling versus tapping, animation performance on the largest boards and text layout remains necessary. The Canvas currently requires visual spatial interaction; it does not implement a nonvisual per-arrow navigation mode.
