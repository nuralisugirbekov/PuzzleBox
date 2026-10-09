# Game design alignment

Game UI now shares the catalog's system surfaces, adaptive appearance, rounded cards and circular glass controls. The existing main navigation, catalog cards and settings are unchanged.

- `UI/GameTheme.swift`: game-specific adaptive colors and surfaces. Separating it from the original Theme leaves onboarding and other existing screens untouched.
- Shared game header: 44-point close/pause/restart controls, title, score and record cards.
- Pause and results: 32-point rounded panels, SF Symbols, capsule buttons and semantic text colors. The result content can scroll when vertical space is limited.
- Game panels, hints, controls, card backs and setup screens use the adaptive tokens. Quick Math and chess no longer force dark mode.
- Canvas arcade/puzzle illustrations and the SpriteKit fruit field retain a dark inset stage, matching the catalog's artwork treatment. Its dark environment is scoped to the drawing surface, not the complete game. Physical piece colors, chess sides, card suits and color-dependent rules retain their distinction.
- Updated text/selected-button contrast in Sudoku, Minesweeper, card games, attention games and setup screens. Reaction Tap still uses green as its semantic go signal.
- Scoring, physics, generated puzzles, timers and persistence were not redesigned.

Source inspection only. No builds, tests, screenshots or simulator runs were performed, per the user's standing preference. Appearance on devices and compact layouts still needs runtime review.
