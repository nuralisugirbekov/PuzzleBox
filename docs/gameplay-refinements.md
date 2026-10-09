# Gameplay refinements — iOS

## Catalog and navigation

102 games remain registered; 92 are visible. Hidden games: Which Side, Circle Jump,
Orbit, Parking Jam, Sky Jump, Brick Breaker, Pong, Higher or Lower, Dominoes, Spades.
Visibility applies to browsing, search, favorites, recent games, rankings, daily picks
and random selection. Stored records are retained.

The catalog now has 10 categories. The result screen has a larger restart action,
a smaller home action, and a random-game action that excludes the current game.
Random navigation replaces the game inside the existing presentation.

## Mechanics

- Pinball: continuously moving flippers, collision response relative to their motion,
  independent left/right hold controls, no repeated powered kick from a stationary
  raised flipper. Simulation uses steps no larger than 1/120 second.
- Draw Bridge: cached drawing path, cached collision segments, bounding-box rejection,
  a single nearest bridge contact per step, and rolling momentum across shallow joints.
- Basket Shot, Paper Toss and Darts: pull back and release; launch direction is opposite
  the drag. Launch positions leave room below for pulling. The guide shows launch direction.
- Avoid: the collision/player position is 45 board units above the touch position.

## Levels

- Bounce: 12 campaign levels (3 existing + 9 new). New ledges rise 55–79 units;
  gaps are 60–80 units. Existing maximum jump rise is approximately 108 units.
- Visual games: 12 reproducible selectable levels per mode, restart keeps the level,
  and winning offers the next level. Differences increase from 3 to 5.
- Pixel Puzzle: 12 picture templates. Rotate Puzzle: original scene plus 11 symbol
  mosaics with asymmetric orientation markers. Tangram: 6 arrangements in 2 orientations.
- Hidden Object, Symmetry and Pattern Match use deterministic per-level content.

## Rules and explanations

First-open help and a reusable How to play button cover Hashi, Kakuro, Nurikabe,
Slitherlink, Futoshiki, Hitori, Takuzu, Tents, Masyu, Nonogram, Number Connect,
Sudoku and Matchstick. Rules and controls use all 8 supported languages.

Source review covered the nine LogicEngine validators and puzzle generation.
Hashi now independently validates geometry and crossing constraints. Loop validation
also checks legal neighboring vertices. Nonogram accepts any grid matching its clues.
Matchstick first selection only targets existing matches; empty destinations become
more visible after selection. One match moves; the equals sign is fixed.

## Verification boundaries

No app build, simulator, device run or test target was invoked, as requested.
A separate mathematical enumeration confirmed that all 625 possible distinct
Matchstick generator candidates have a valid one-match reverse solution, including
its fallback. All 12 Slitherlink source boundary variants form a connected single loop.
Source delimiters and localization duplicate keys were checked. These checks do not
replace Swift compilation or interactive validation. Pinball feel, bridge frame time,
layout on small screens and touch controls still need device verification.
