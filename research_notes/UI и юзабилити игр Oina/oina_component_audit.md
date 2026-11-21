# Oina: audit of the current UI components and shared game flow (from the code and screenshots, 2026-11-14)

Source files: `PuzzleBoxApp/UI/ToyMaterial.swift`, `UI/GameContainerView.swift`, `UI/GameCelebration.swift`, `UI/GameTutorialView.swift`. This is first-hand inspection of the app, not web research.

## Shared skeleton (every game, `ToyGameStage`)
- Row 1: pause `ToyIconButton` (44 pt circle) top-left, game tools top-right (undo/hint/reset/lives).
- Centre top: a 64 pt black rounded "debossed" number (score or clock) with "Your best · n" or a caption (moves, difficulty) under it.
- Row 2: pill chips (`ToyChip`, 34 pt tall): level menu on the left, a status (moves left, stars, painted cells) on the right.
- Then the board in a raised `toyTray`, then a hint line that fades out after the first move.
- Result: about 30 % of the screen height is chrome before the board starts; the biggest element is the score, not the goal or the board. All 35 games look structurally identical; only the colours change.

## Components and their problems
1. **ToyBlock (base of every button, chip, tray, window)**
   - Construction: the lip is a full copy of the shape filled 20 % darker and offset down by `lip` (3–8 pt). The face is drawn on top with a vertical gradient, and a 1.5 pt white→clear stroke traces the whole outline inset by 1 pt (it fades by the vertical centre, so the sides and top get a light ring). There are two drop shadows (radius 1 and radius 10).
   - Visual result (seen in the pause menu close-up): the face's bottom edge is a sharp curve sitting on another identical curve, so the lip reads as a separate crescent shape and not as the side wall of one solid object. The light ring makes an "outline inside an outline". The user's words: "two rounded rectangles stacked on top of each other".
   - There is no side wall: the lip's ends at the capsule's left and right are as thick as at the bottom, and there is no gradient on the lip.
2. **ToyPressStyle (pressed state)**
   - Bug: `ToyBlock(pressed:)` already sinks the face by 0.6 × lip, and the button style also offsets the whole label and background by 0.6 × lip. The face therefore moves 1.2 × lip, past the bottom of its own lip, and the lip moves too.
   - The spring has damping 0.6, so the button bounces on release.
   - There is no disabled state; callers dim things by hand (for example the chess hint uses opacity 0.5).
   - `Haptics.soft()` fires on every press-down of every button.
3. **ToyIconButton:** a 44 pt circle (meets the minimum). The glyph is 40 % of the size, bold rounded. The same white clay is used for pause, undo, hint and close, so there is no hierarchy.
4. **ToyChip:** 34 pt tall plus a 3 pt lip. It is used both for read-only status and as the label of a level `Menu`, so a tappable chip is under 44 pt and looks the same as a non-tappable one (affordance problem).
5. **ToyCapsuleButton:** minimum height 38 pt, so under 44 pt. Text is `.subheadline` bold with `minimumScaleFactor(0.6)`, which shrinks the text instead of growing the button.
6. **Debossed headline (`toyDeboss`):**
   - Fixed size: a 64 pt system font that does not follow Dynamic Type.
   - The colour is the backdrop mixed only slightly (deboss mix 0.06), plus a 1.5 pt light rim shadow.
   - In screenshots the main score ("0", "00:01", "0:53") is barely visible: contrast is roughly 1.1–1.4:1 against the backdrop, far below 3:1 (WCAG 1.4.11) and 4.5:1 (1.4.3). The most important number on screen is the least legible.
7. **toyTray (board frame):** ToyBlock with an 8 pt lip under the board. It shows the same stacked-lip artefact, very visible on big trays (Simon console, Mini Golf frame, Chess frame).
8. **ToySocket:** a well with a top inner shade. Fine, but very low contrast against the tray in several worlds (Arrow Escape cells are almost invisible).
9. **Windows (PauseAlert, ResumeAlert, GameOverOverlay):**
   - Fixed width 300 pt, used by every game.
   - The game-over card is the same for win and lose and for every game: a glyph, the title, the score in a well, best, Play again, Home.
   - The ✕ close button is 40 pt (under 44).
   - There are no stars, no per-level result, and no "next level" button. A won level auto-advances after 1.7 s, so the player cannot stay on the result.
   - There is no shared "fail → retry / continue" design per genre.
10. **TapToStartCard:** a toy card with a pulsing hand. It blocks the board, does not teach the mechanic, and is not interactive itself (hit-testing is off; the game behind takes the tap).
11. **Tutorial (`GameTutorialView`):**
    - It is a system sheet (medium/large detents) with two text paragraphs (Rules, Controls), a system blue `.borderedProminent` "Got it" button and a navigation "Done". This ignores the game's world colours.
    - On first launch the game opens paused with the pause window visible behind the sheet.
    - It is a wall of text, not teach-by-doing.
12. **Hint line:** footnote text at 0.6 opacity in the game ink. It is small and low contrast, and it is the only onboarding inside the game.
13. **Colours:** each game has its own palette (`ToyPalette`: backdrop gradient, tray, socket, ink, deboss, card, accent). Dark mode is handled by dynamic colours. Accent text on light backdrops (for example the orange "Move 1 match", the coral counters) has not been checked for contrast.
14. **Motion:** the score bumps on increase, content scales in at 0.95 on open, and windows use opacity plus a slight scale. Reduce Motion is respected in some places (score bump, count-up), but not for every pulse (`symbolEffect(.pulse, options: .repeating)` on the start card).

## Observed per-flow facts
- **Start:** some games need "Tap to start" (arcades, golf); puzzles start immediately; Simon has its own Start button; Chess has a separate setup screen (pick a duration).
- **Pause:** the same three or four stacked buttons in every game (Resume, Restart, How to play, Home).
- **Resume a saved game:** the same window with a question mark glyph.
- **Level selection:** a dropdown `Menu` behind a chip ("Level 1 of 100"). There is no level map and no progress visualisation.
