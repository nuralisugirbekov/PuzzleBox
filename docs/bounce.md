# Bounce (iOS)

An original compact platform game inspired by the red-ball games on older phones. Uses three new layouts and code-drawn scenery, without imported Nokia levels or assets.

- Hold left/right to roll; tap jump while holding a direction to cross gaps.
- Collect every ring to open the exit. Three levels, three lives for the whole run.
- Rings score 50 points, level completion 250, finishing all levels adds 100 per remaining life.
- Death returns to the current level's start. Collected rings persist and cannot award points twice.
- Horizontal camera, solid floors/platform undersides, spikes and gaps, brief respawn protection, buffered jump and short edge-jump grace period.
- Shared pause, restart, analytics, records and result UI; translations in all eight languages.
- Controls release on pause, backgrounding and gesture cancellation. Simulation uses capped, subdivided steps.

Sources: `PuzzleBoxApp/Games/Bounce/BounceEngine.swift`, `BounceView.swift`; registered as `GameID.bounce`.

Source inspection only. No build, tests, simulator or device run, per user preference. Layout and level difficulty still need runtime verification.
