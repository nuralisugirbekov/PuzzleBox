# iOS arcade collection

Thirteen additional games are registered in `GameCore.swift`. They use the existing game container, pause and result overlays, local high scores, and `level_start`, `level_end`, `post_score`, and record analytics. Android is unchanged. Every new title, hint, and status message is available in all eight existing languages.

These are minimal original interpretations of the requested mechanics, with procedural graphics. They are not asset or level copies of commercial games. No build, simulator session, or automated app tests were run, as requested; compilation, touch feel, and difficulty tuning remain unverified on a device.

## Rules

- Stack: tap to stop a moving block. Only overlap with the previous block survives. A miss ends the round; each successful layer scores 10. Near-perfect drops snap within 5 world units; removed parts fall away.
- Color Jump: repeated taps propel the ball upward through a moving four-color gate. Touching the wrong segment loses. Crossing the gate scores 10 and changes the ball's color. The gate is horizontal in this 2D interpretation.
- Knife Spin: launch pins into a rotating target. Hitting an existing pin loses. Each pin scores 10; completed targets increase speed and add pre-existing pins.
- Helix Drop: drag horizontally to shift circular platform gaps. The platforms are shown as unwrapped 2D strips. The ball falls through gaps, bounces on safe sections, and loses on red. Each passed platform scores 10.
- Sky Jump: the ball bounces automatically; horizontal dragging steers it onto platforms. The camera follows ascent. Score is height divided by 10. Falling below the screen loses.
- Flappy Flight: tap to lift the character through pipe gaps. Crossing a pair scores 10; wall, ceiling, and floor collisions lose.
- Brick Breaker: drag the paddle. Each brick scores 10, three lives, clear all 30 bricks to win.
- Pong: drag the bottom paddle against a speed-limited bot. First to seven wins; player points are the score.
- Road Hop: tap forward or swipe in a direction. Traffic moves in alternating lanes; every fourth row is safe. Each new row scores 10. Car collision loses.
- Reaction Tap: wait for the green cue, then tap. Five measured trials, three false starts allowed. Each trial scores `max(0, 1000 - reactionMilliseconds)`. The result shows average reaction time. Measurements use monotonic timestamps, and pausing/backgrounding cancels a pending cue to avoid prepared answers.
- Simon: repeat four colored, symbol-marked buttons. Each cleared sequence adds one element and awards `sequenceLength × 10`. Input is disabled during demonstration. A mismatch loses.
- Higher or Lower: predict whether a uniformly sampled integer from 1 through 100 will be higher or lower than the current number. Equal values are excluded. Ten rounds, three lives, 10 points per correct prediction. The previous and new number remain visible briefly after each guess.
- Merge Fruit: tap a horizontal position to drop a fruit into a physics container. Equal touching fruits merge to the next size and award `10 × 2^newStage`. The largest fruit no longer merges. Overflow above the red line for 1.2 active seconds loses; newly created fruit has a 1.5-second settling grace period. Drops have a 0.55-second cooldown.

## Implementation

`ArcadeEngine.swift` uses a fixed 320×480 world and substeps of at most 1/120 second. Rendering and touch coordinates are scaled together. Simulations stop while paused or inactive. Restart clears all entities and timers; no delayed game tasks outlive the round.

`BrainArcadeView.swift` uses the same shared pause state and a small timed state machine for cues and playback. No question can be skipped by tapping during feedback.

`MergeFruitView.swift` uses SpriteKit physics. Contact callbacks enqueue pairs; scene updates perform merges outside the physics simulation callback, as required by [Apple's contact delegate documentation](https://developer.apple.com/documentation/spritekit/skphysicscontactdelegate). Already consumed nodes are skipped to prevent duplicate merges. SpriteKit pauses with the game or app lifecycle.
