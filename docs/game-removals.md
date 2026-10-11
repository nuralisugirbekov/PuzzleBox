# iOS game removal — 2026-10-09

The active iOS catalog now contains 50 games. 52 games were removed from the
registry, navigation, mode enums, shared engine/view branches and dedicated files.
Match-3 artwork and 175 unused localization keys were removed in all 8 languages.

Number Connect (Numberlink), Nonogram and Mini Sudoku are retained, including
rules, controls, records and routes. Mini Sudoku's source is unchanged.

On the next launch, StatsStore removes records, favorites, recent-game entries,
tutorial flags and the cached daily pick belonging to unregistered games.
All picks now use the remaining registry; no hidden-game list remains.

No build, app launch or test target was run. Swift syntax parsing passed, and
source checks confirmed metadata/routes for all 50 games and no view references
to deleted shared-engine members. This does not constitute compilation or device QA.

Removed IDs:

ascending, avoid, balanceScale, biggestNumber, brickBreaker, cannonShot, circleJump, colorJump, darkTiles, darts, dash, dominoes, dontTap, drift, fastSort, foldIt, futoshiki, gravityFlip, hashi, hiddenObject, higherLower, hitori, kakuro, keepItUp, laneSwitch, masyu, match3, memoryFlash, missingNumber, nurikabe, oddOneOut, orbit, paperToss, parkingJam, patternMatch, pinballMini, pixelPuzzle, pong, ricochet, sameGame, shadowMatch, skyJump, slitherlink, spades, spotDifference, symmetry, takuzu, tangram, tents, wallJump, whichSide, zigZag
