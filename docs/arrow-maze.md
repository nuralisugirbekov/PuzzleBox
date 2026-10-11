# Arrow Maze — iOS implementation specification

## Scope and gameplay

Native iOS 17+ game integrated into PuzzleBox with SwiftUI chrome, a UIKit `SKView`, and SpriteKit rendering. No third-party packages or downloaded assets are required. The six authored levels range from 9×11 to 15×17 cells. Corridors are 72 world points wide; forward speed increases from 100 to 125 points/second. All levels are selectable from the level menu.

The arrow starts stationary behind a start button. Once started, it moves continuously. A tap in the **left half of the maze** turns it 90° counterclockwise; a tap in the **right half** turns it 90° clockwise. Two labeled buttons provide the same commands. Left/right refer to the arrow's heading, not the screen's vertical direction. Only one touch is accepted. Input has a 120 ms cooldown, measured in active simulation time.

Collect every yellow gem to unlock the green exit. Contact with a wall ends the round. A locked exit is traversable but cannot complete the level. Victory exposes the existing next-level action when another level exists; retry, home, and random-game actions use PuzzleBox's shared result UI. Scores are per attempt, not accumulated across levels:

```
score = 100 × collectedGems
      + (escaped ? 500 + max(0, 300 − floor(activeSeconds) × 5) : 0)
```

The speed bonus uses simulated active time. Pauses and background time do not count. After a long rendering stall, excess wall-clock time is deliberately discarded; this is a local casual-game scoring policy, not a competitive server-authoritative timer.

## Source responsibilities and ownership

- `ArrowMazeLevel.swift`: immutable cell geometry, cardinal headings, guaranteed solution routes, connected dead ends, gem placement, and six level definitions. Initializer preconditions reject disconnected branch starts, diagonal/zero-length segments, and open outer borders. Gems are placed along straight portions of the authored solution route.
- `ArrowMazeSimulation.swift`: value-type rules, movement, turn assistance, swept wall checks, idempotent collection, exit conditions, score, and terminal outcome. No SpriteKit objects, timers, persistence, or haptic side effects.
- `ArrowMazeEngine.swift`: main-actor observable adapter implementing `GameEngine`. Owns the simulation and publishes state, score, gem count, selected level, and restart revision. Simulation storage is observation-ignored: position changes do not invalidate the SwiftUI hierarchy every frame.
- `ArrowMazeScene.swift`: nodes, touch input, fixed-step scheduling, contact buffering, trail, and tracking camera. Holds a weak engine reference. All state mutation and SpriteKit interaction happen on the main actor.
- `ArrowMazeView.swift`: shared game container, level selector, HUD, start overlay, controls, lifecycle observation, and `UIViewRepresentable` bridge. Its coordinator owns one scene per `SKView`; teardown pauses rendering, clears the contact delegate, and detaches the scene.

Data flow: touch/button → engine command → simulation → observable HUD/result and scene rendering. SpriteKit contact callbacks buffer identifiers; the next update processes them through the same simulation rules. The shared container owns persistence and round analytics. There are no per-frame analytics events.

## Movement and frame cycle

The scene accumulates the interval from `SKScene.update(_:)`, clamps an incoming frame to 1/15 second, and executes up to eight 1/120-second simulation steps. Movement follows the requested equation:

```swift
let dx = cos(heading.angle) * level.speed * CGFloat(dt)
let dy = sin(heading.angle) * level.speed * CGFloat(dt)
```

Cardinal headings represent θ ∈ {0, π/2, π, 3π/2}. SpriteKit coordinates start at the bottom left, with positive y pointing up. After simulation steps, the scene copies the model position and angle to the visible arrow, updates its independent tip sensor, removes collected gem nodes, rebuilds the bounded trail, and updates the camera. SpriteKit then performs its physics phase. Contact callbacks do not remove or add nodes during physics evaluation.

The first frame after start/resume only establishes a time baseline. Pause, backgrounding, restart, and teardown clear the accumulator and pending contacts. Backgrounding a started round sets the engine to paused; foregrounding requires the normal explicit Resume action. An unstarted level remains ready to start.

## Turning and collision authority

If the arrow center is within 18 points of the current cell center, a turn first aligns it to that center. The alignment segment is checked for walls. Outside this assistance region the turn occurs at the current position. Eight segments approximate the quarter-circle swept by the tip while turning. Invalid alignment or rotation ends the attempt. Rotation is immediate; there is no interpolated visual angle that disagrees with the hitbox.

The model checks both a 10-point body envelope and a 4-point tip envelope, whose center lies 18 points ahead of the arrow center. A segment/AABB slab test checks the motion against expanded nearby wall cells. Expanded rectangular bounds are conservative at corners. Cells outside the maze are walls. This authoritative swept check prevents skipping thin boundaries even though the SpriteKit sensor is positioned manually. `usesPreciseCollisionDetection` is enabled as an additional physics setting, not relied upon as a substitute for the model's sweep.

Physics categories:

- arrow tip: `1 << 0`, dynamic, gravity and rotation disabled, zero damping;
- walls: `1 << 1`, static rectangular bodies merged into horizontal runs;
- gems: `1 << 2`, static circles with radius 10;
- exit: `1 << 3`, static circle with radius 22.

All collision masks are zero: impacts produce failure, not a bounce. The arrow requests contacts with walls, gems, and the exit through `contactTestBitMask`; static sensors request none. The tip sensor is a separate world-space node, avoiding nested dynamic-body transforms. Callback contacts are revalidated against the current model pose before being accepted. Wall failure takes priority when processing coincident callback rewards. Terminal simulation outcomes ignore further input/contacts, and collected gem IDs form a set to prevent duplicate rewards.

## Camera, trail, and rendering

An `SKCameraNode` is retained and attached to the scene. Its desired position is the arrow center plus a 54-point forward offset, clamped to keep the viewport inside maze bounds. Tracking uses frame-rate-independent exponential interpolation:

```
alpha = 1 − exp(−8 × frameDelta)
camera += (target − camera) × alpha
```

The camera maintains at least a 360-point-wide world viewport on narrow screens. At level load and resize it snaps to a valid target. Reduce Motion removes the forward offset and tracking lag and hides the outer trail glow; motion intrinsic to gameplay remains.

The arrow has a tail child at (−10, 0). World-space tail samples generate a `CGPath` shared by two `SKShapeNode`s: a 3-point cyan line and a faint 9-point outer line. Samples require 2.5 points of movement, expire after 0.8 active seconds, and are capped at 72. Rounded line joins preserve sharp gameplay turns without particle allocation. Rendering targets 60 fps; simulation uses 120 Hz substeps. Static wall runs are merged to limit physics bodies. Nearby-cell collision queries avoid scanning every wall.

SwiftUI HUD and controls use the existing adaptive theme, while the maze uses a dark high-contrast palette. Text is localized for English, Russian, Kazakh, French, Hindi, German, Simplified Chinese, and Korean. Controls are at least 48 points high, have textual accessibility labels, and offer a button alternative to touch halves. This real-time spatial game does not yet provide a fully nonvisual navigation mode.

## Integration and extension

`GameID.arrowMaze` supplies metadata and routes to `ArrowMazeView`. Existing catalog, search, random selection, favorites, best scores, and round analytics discover it through `GameID.allCases`. `GameTutorial.forGame` provides rules and controls with the existing first-play/help presentation. Adding this game brings the current iOS catalog to 51 entries.

To add a level, append an axis-aligned waypoint route plus connected branch segments to `ArrowMazeLevel.all`. Keep an outer wall border and sufficient turn clearance. Gem placement derives from the route. Score/speed/assistance constants are explicit and can be tuned without changing rendering. Level progress and a paused attempt are not persisted across process termination; existing best-score persistence remains in use.

## Validation status and handoff

No app build, simulator session, or test execution was performed, following the user's request. Added Swift Testing cases cover solution routes, duplicate collection, swept-wall geometry, terminal behavior, and engine pause/restart. These tests still need to be run in Xcode. Production release acceptance also requires device verification of touch timing, interruptions/resume, small-screen layout and Dynamic Type, repeated level changes and teardown, and Instruments frame-time/memory measurements. Performance targets above are design targets, not measured results.

## Apple references

- [SpriteKit frame-cycle events](https://developer.apple.com/documentation/spritekit/responding-to-frame-cycle-events)
- [Physics contact masks](https://developer.apple.com/documentation/spritekit/skphysicsbody/contacttestbitmask)
- [Scene camera](https://developer.apple.com/documentation/spritekit/skscene/camera)
- [SpriteKit physics programming guide](https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/SpriteKit_PG/Physics/Physics.html)
