# Apple Human Interface Guidelines for casual iPhone game UI (SwiftUI)

Scope note: sources are the current HIG pages, read through Apple's own JSON data endpoints (developer.apple.com/tutorials/data/design/human-interface-guidelines/*.json, which serve the same content as the public HIG URLs below), plus three Apple video sessions: WWDC24 "Design advanced games for Apple platforms" (10085), Meet with Apple 2025 "Design great interfaces for handheld games" (243), and WWDC26 "Make your game great with touch" (358). Retrieved 2026-11-14. Quotes are verbatim from those pages. The Meet with Apple 243 transcript is auto-generated, so a few quotes contain transcription errors.

## 1. Game screen layout, HUD placement, safe areas, Dynamic Island / home indicator, touch controls, letting the game own the screen

### Takeaway
Apple's rule is to let the game art run full-bleed to every pixel, while keeping all interactive UI and critical information inside the safe area, away from rounded corners, the Dynamic Island and the Home indicator. Anchor the UI in sections to screen edges rather than scaling one fixed layout. Put frequent actions near the thumbs, put menus and secondary controls at the top, and keep the center of the screen clear. Apple has no HUD-specific rule; HUD guidance follows from the safe-area, control-placement and text-size rules.

### Cited Findings
- Safe areas defined: "A safe area defines the area within a window that isn't covered on the edge by a hardware feature or another view... Respecting the safe area is essential to make sure system UI and hardware features like the Dynamic Island don't obstruct content and controls." — [HIG Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- "Make sure to position buttons where they don't overlap system features like the Home indicator or Dynamic Island on iPhone. Place frequently used buttons near a player's thumb, avoiding the circular regions where players expect movement and camera input to happen. Place secondary controls, like menus, at the top of the screen." — [HIG Game controls](https://developer.apple.com/design/human-interface-guidelines/game-controls)
- "Safe areas help you avoid the system's Home Indicator and gesture regions, as well as the Dynamic Island on iPhone, all of which could potentially overlap your controls." — [Meet with Apple: Design great interfaces for handheld games](https://developer.apple.com/videos/play/meet-with-apple/243)
- Full-bleed: "Remember, safe areas are meant as guides for positioning UI, but aren't meant to be the actual margins for your entire game." / "Take advantage of every pixel on the screen for your game's environment." — [WWDC24 Design advanced games](https://developer.apple.com/videos/play/wwdc2024/10085/)
- Letterboxing: "If there's important content in your game that's getting clipped by device proportions, first try adjusting your game's camera" and "only use letterboxing if you have to, your game will always feel more immersive if it makes use of the entire screen." — [WWDC24 10085](https://developer.apple.com/videos/play/wwdc2024/10085/)
- Full-screen backgrounds: "For full-screen background content, be sure to extend it underneath sidebars, toolbars, and tab bars to fit the entire screen or window." Do not change artwork's aspect ratio; "scale it so that it fills the screen completely." — [HIG Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- Sectioned layout: "break your UI layout into separate sections. Each of which is anchored to a specific side of the screen... This keeps controls at physically comfortable sizes for mobile players." — [WWDC24 10085](https://developer.apple.com/videos/play/wwdc2024/10085/); "Simple scaling puts things in unpredictable locations and makes them difficult to reach, too small or too large." — [Meet with Apple 243](https://developer.apple.com/videos/play/meet-with-apple/243)
- WWDC26: the Touch Controller framework "provides nine anchor points for each layout." Add `safeAreaInsets` to control offsets: "Because I applied safe areas to the offsets, the Dynamic Island doesn't overlap any of my controls." Also: "no controls will go in the center of the display." — [WWDC26 Make your game great with touch](https://developer.apple.com/videos/play/wwdc2026/358/)
- Aspect ratios: "Games need to look good and behave well at various aspect ratios, such as 16:10, 19.5:9, and 4:3." In-game menus must "remain legible and easy to use on every device — and, if you support them, in both orientations on iPhone and iPad — without obscuring other content." "Avoid fixed layouts as much as possible." — [HIG Designing for games](https://developer.apple.com/design/human-interface-guidelines/designing-for-games)
- "Even if your app is locked to a certain orientation, such as a landscape-only game, it's still important to ensure your interface resizes well." "Determine layout based on size classes, not device type or orientation." — [HIG Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- Direct touch over virtual controls: "Look for opportunities to reduce the amount of virtual controls that overlap your game content by associating actions with in-game gestures instead. For example, consider letting players tap objects to select them instead of adding a virtual selection button." — [HIG Game controls](https://developer.apple.com/design/human-interface-guidelines/game-controls)
- Hide what isn't usable: "You can hide controls when an action isn't available or relevant, letting you reduce clutter." — [HIG Game controls](https://developer.apple.com/design/human-interface-guidelines/game-controls); "when an action isn't available or relevant, remove it from the screen entirely. Don't leave controls visible that players can not use." — [WWDC26 358](https://developer.apple.com/videos/play/wwdc2026/358/)
- Controls can show state: "I'm using the Fire button to visually represent when the ability will be available to use again." — [WWDC24 10085](https://developer.apple.com/videos/play/wwdc2024/10085/)
- Glyphs: "Choose artwork that visually represents the action each button performs... Avoid using abstract shapes or controller-based naming like A, X, or R1 as artwork." — [HIG Game controls](https://developer.apple.com/design/human-interface-guidelines/game-controls)
- Multi-press: "Consider redesigning game mechanics that require players to press multiple buttons at the same time or in a sequence. Leverage gestures such as double tap and touch and hold to provide different variations of the same action." — [HIG Game controls](https://developer.apple.com/design/human-interface-guidelines/game-controls)
- Input areas: "expand the input area to be as broad as possible"; for overhead or isometric games, "consider letting a player tap to move" and "use a two finger pinch to zoom." — [WWDC24 10085](https://developer.apple.com/videos/play/wwdc2024/10085/)
- Menus: "when I show my menu, I hide all my controller UI completely. It's crucial that your menus respond to touch." — [WWDC24 10085](https://developer.apple.com/videos/play/wwdc2024/10085/)
- Full screen: "In macOS, iOS, and iPadOS, full-screen mode lets people hide other apps and parts of the system UI." — [HIG Designing for games](https://developer.apple.com/design/human-interface-guidelines/designing-for-games)
- Tooling: safe-area templates are in the Apple Design Resources, and Simulator can preview "different device models, bezels, and orientations." — [WWDC24 10085](https://developer.apple.com/videos/play/wwdc2024/10085/)

### Inferences
- For a SwiftUI puzzle game: apply `.ignoresSafeArea()` to the board background or art layer only. Keep the HUD (score, moves, timer, pause) inside the safe-area insets in a top bar, since status is secondary. Keep primary actions (hint, undo) in the bottom thumb zone above the Home indicator.
- Tap-on-object interaction, which most puzzle games use, is exactly what Apple prefers over virtual buttons. Keep extra on-screen buttons to a minimum.
- When a pause or menu sheet opens, hide or disable the in-game controls underneath it.

### Gaps
- None of the sources reviewed has a "HUD" section or uses the term, so HUD rules are inferred from the safe-area, control-placement and text-size guidance.
- None of the sources reviewed covers system edge swipes, deferring system gestures (`defersSystemGestures` / `persistentSystemOverlays`) or hiding the status bar.

## 2. Buttons: shapes, hit targets, spacing, pressed states, custom game buttons, hierarchy, Liquid Glass

### Takeaway
On iOS, aim for 44×44 pt (the default). 28×28 pt is the floor, and only for less important controls such as menus. Leave about 12 pt of padding around bezeled controls and about 24 pt around unbezeled ones. Every custom or virtual button must have a press state, ideally one that is still visible under the finger, paired with sound and haptics. Use no more than one or two prominent buttons per view, and use style rather than size to mark the preferred one. Liquid Glass belongs to the controls/navigation layer, sparingly, and never to the content layer.

### Cited Findings
- "As a general rule, a button needs a hit region of at least 44x44 pt — in visionOS, 60x60 pt." — [HIG Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
- Table: iOS/iPadOS default control size 44×44 pt, minimum 28×28 pt. — [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- Games: "Make sure frequently used controls are a minimum size of 44x44 pt, and less important controls, such as menus, are a minimum size of 28x28 pt." — [HIG Game controls](https://developer.apple.com/design/human-interface-guidelines/game-controls)
- "Buttons that are too small or too close together can frustrate players and make gameplay less fun." The page's prose says "buttons in iOS must be at least 44x44 pt," while its table lists a 28×28 pt minimum. — [HIG Designing for games](https://developer.apple.com/design/human-interface-guidelines/designing-for-games)
- 28 pt caveat: "buttons at this size can be harder to select accurately, especially if your players have their attention on your gameplay." "For both text and buttons, aim for the defaults rather than the minimums." — [WWDC24 10085](https://developer.apple.com/videos/play/wwdc2024/10085/)
- Spacing: "add about 12 points of padding around elements that include a bezel. For elements without a bezel, about 24 points of padding works well around the element's visible edges." — [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- "It's essential to include enough space around a button so that people can visually distinguish it from surrounding components and content." — [HIG Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
- Press state: "Always include a press state for a custom button. Without a press state, a button can feel unresponsive." — [HIG Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
- Games press state: "add a visual press state effect, such as a glow, that they can see even when their finger is covering the control. Combine this press state with sound and haptics." — [HIG Game controls](https://developer.apple.com/design/human-interface-guidelines/game-controls); "could be as simple as darkening or highlighting buttons when pressed... draw visual effects like a glow outside of the bounds of the control." — [WWDC24 10085](https://developer.apple.com/videos/play/wwdc2024/10085/); "Every touch control you create should have a visible pressed state." — [WWDC26 358](https://developer.apple.com/videos/play/wwdc2026/358/)
- Hierarchy: "use a button that has a prominent visual style for the most likely action in a view." "Keep the number of prominent buttons to one or two per view." "Use style — not size — to visually distinguish the preferred choice." "Don't assign the primary role to a button that performs a destructive action, even if that action is the most likely choice." — [HIG Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
- Custom style restrictions: "Avoid creating a custom button that uses a white background fill and black text or icons. The system reserves this visual style to convey the toggled state." "Avoid applying a similar color to button labels and content layer backgrounds." "If your app already has bright, colorful content in the content layer, prefer using the default monochromatic appearance of button labels." — [HIG Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) (Liquid Glass guidance updated Dec 16, 2025)
- Activity: on iOS, show an activity indicator for actions that don't complete instantly ("Checkout" becomes "Checking out…"). — [HIG Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
- Liquid Glass (iOS 26+, guidance added June 9, 2025 and updated Sept 9, 2025): it "forms a distinct functional layer for controls and navigation elements... that floats above the content layer." "Don't use Liquid Glass in the content layer." "Use Liquid Glass effects sparingly... Limit these effects to the most important functional elements." — [HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- "Only use clear Liquid Glass for components that appear over visually rich backgrounds." With clear glass over bright content, "consider adding a dark dimming layer of 35% opacity." Use the regular variant "when background content might create legibility issues, or when components have a significant amount of text." APIs: `glassEffect(_:in:)`, `Glass.regular`, `Glass.clear`. — [HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- Liquid Glass color: "Apply color sparingly... To emphasize primary actions, apply color to the background rather than to symbols or text... Refrain from adding color to the background of multiple controls." — [HIG Color](https://developer.apple.com/design/human-interface-guidelines/color)
- Motion: "the movement of Liquid Glass responds to direct touch interaction with greater emphasis to reinforce the feeling of a tactile experience." — [HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion)

### Inferences
- Tactile-toy game buttons fit the HIG if they have at least a 44 pt hit area (`.contentShape` plus a frame), a press state (scale or darken plus glow), light haptics on touch-down, and no more than one prominent CTA per screen (for example "Play again" on the results screen, with secondary actions styled differently).
- The board itself is content, so it should not be glass. Glass could be used for the HUD bar or pause button floating above the board, and then sparingly. The regular variant is preferable over busy boards.
- Destructive actions such as "Quit" or "Restart" should not be the prominent or primary button.

### Gaps
- None of the sources reviewed gives a numeric corner-radius or shape rule for buttons, or a press-animation duration.
- The Buttons page does not say how Liquid Glass responds to Reduce Transparency or Increase Contrast beyond noting that its appearance "can differ."

## 3. Typography: Dynamic Type in games, minimum sizes, legibility over game art

### Takeaway
On iPhone, game text should be 17 pt by default and never below 11 pt, using Regular weight or heavier. Support Dynamic Type, or failing that an in-game text-size setting, with enlargement to 200% as the ideal. Over busy game art, add contrast or a visible background shape. When text overflows, scroll rather than shrink it.

### Cited Findings
- iOS/iPadOS default text size 17 pt, minimum 11 pt. — [HIG Typography](https://developer.apple.com/design/human-interface-guidelines/typography); [HIG Designing for games](https://developer.apple.com/design/human-interface-guidelines/designing-for-games)
- "On iPhone and iPad, aim for a type size of 17 points or higher... For less essential information, try not to go lower than an 11 point type size." "Use scroll views if you have an overflow of information, instead of reducing type sizes." — [WWDC24 10085](https://developer.apple.com/videos/play/wwdc2024/10085/); "the smaller a device is, the larger your text should be." — [Meet with Apple 243](https://developer.apple.com/videos/play/meet-with-apple/243)
- Dynamic Type Large (default) on iOS, in pt (leading): Large Title 34 (41), Title 1 28 (34), Title 2 22 (28), Title 3 20 (25), Headline 17 semibold (22), Body 17 (22), Callout 16 (21), Subhead 15 (20), Footnote 13 (18), Caption 1 12 (16), Caption 2 11 (13). — [HIG Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- "avoid Ultralight, Thin, and Light font weights"; "If you use a custom font with a thin weight, aim for larger than the recommended sizes." — [HIG Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- "If you use a custom font, make sure it implements the same behaviors" (Dynamic Type, Bold Text). For games: "be sure to let players adjust text size in other ways." — [HIG Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- "Ideally, give people the option to enlarge text by at least 200 percent." — [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- Games: "test game text for legibility on each platform"; "Increasing text size and adding visible background shapes can help make text easier to read"; "people are often more interested in a character's dialog than in transient hit-damage values." — [HIG Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- "If you need to display three or more lines of text, avoid tight leading." — [HIG Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- Let players customize "type size, game control mapping, motion intensity, and sound balance." — [HIG Designing for games](https://developer.apple.com/design/human-interface-guidelines/designing-for-games)

### Inferences
- In SwiftUI, use `.font(.system(.body, design: .rounded))`-style text styles, or `@ScaledMetric` and `Font.custom(_:size:relativeTo:)` for custom fonts, so HUD numbers scale. Cap growth with `dynamicTypeSize(...DynamicTypeSize.accessibility2)` where the board layout would break, rather than ignoring Dynamic Type.
- HUD labels such as "Moves" or "Best" at 11 to 12 pt are the floor. The score value itself should be 17 pt or larger.

### Gaps
- None of the sources reviewed recommends a maximum Dynamic Type cap specifically for game HUDs.

## 4. Colour and contrast

### Takeaway
Use WCAG AA contrast as the target: 4.5:1 for text up to 17 pt, and 3:1 for 18 pt and larger or bold text. Provide light, dark and Increase Contrast variants of custom colours, never rely on colour alone, and use colour meanings consistently.

### Cited Findings
- Contrast table: up to 17 pt (all weights) 4.5:1; 18 pt 3:1; bold (all sizes) 3:1. WCAG and APCA are named as sources. — [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- "If your app doesn't provide this minimum contrast by default, ensure it at least provides a higher contrast color scheme when the system setting Increase Contrast is turned on... check the minimum contrast in both light and dark appearances." — [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- "If you define a custom color, make sure to supply light and dark variants, and an increased contrast option for each variant... Even if your app ships in a single appearance mode, provide both light and dark colors to support Liquid Glass adaptivity." — [HIG Color](https://developer.apple.com/design/human-interface-guidelines/color)
- "Avoid relying solely on color to differentiate between objects, indicate interactivity, or communicate essential information... use text labels or glyph shapes." — [HIG Color](https://developer.apple.com/design/human-interface-guidelines/color); for games specifically, avoid "relying solely on color to convey an important detail." — [HIG Designing for games](https://developer.apple.com/design/human-interface-guidelines/designing-for-games)
- "Consider allowing people to customize color schemes such as chart colors or game characters." — [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- "Avoid using the same color to mean different things." "Test your app's color scheme under a variety of lighting conditions." — [HIG Color](https://developer.apple.com/design/human-interface-guidelines/color)
- "Consider how the colors you use might be perceived in other countries and cultures." — [HIG Color](https://developer.apple.com/design/human-interface-guidelines/color)

### Inferences
- Colour-coded tiles and blocks (for example 2048 values or block colours) should also carry numbers, shapes or patterns. A colour-blind-safe palette option fits the "customize color schemes" advice.
- Even a game with a fixed dark theme should define light, dark and high-contrast asset colours, because Liquid Glass adapts to them.

### Gaps
- None of the sources reviewed gives a numeric contrast rule for non-text UI elements such as icons and borders (WCAG's 3:1 for non-text is not restated by Apple).

## 5. Accessibility: VoiceOver, Reduce Motion, Reduce Transparency, Increase Contrast, Button Shapes, haptics

### Takeaway
Apple expects games to honour system settings by default (read accessibility settings for defaults), to label every custom element for VoiceOver, to respond to Reduce Motion by cutting zoom, scale and peripheral motion, to pair audio with haptics and visuals, to offer difficulty accommodations, and to make haptics optional.

### Cited Findings
- Defaults: use device information, including "the player's accessibility settings." — [HIG Designing for games](https://developer.apple.com/design/human-interface-guidelines/designing-for-games)
- VoiceOver: "Add labels to any custom elements your app defines. Be sure to keep your descriptions up-to-date"; "Exclude purely decorative images"; "Inform VoiceOver when visible content or layout changes occur"; "Specify how elements are grouped, ordered, or linked." The page says "No additional considerations for iOS." — [HIG VoiceOver](https://developer.apple.com/design/human-interface-guidelines/voiceover)
- Reduce Motion: "ensure your app or game responds by reducing automatic and repetitive animations, including zooming, scaling, and peripheral motion." Techniques: tighten springs to reduce bounce, track animations directly with gestures, avoid animating z-axis depth changes, replace x/y/z transitions with fades, and avoid animating into or out of blurs. — [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- "Make motion optional... avoid using it as the only way to communicate important information." — [HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion)
- Games: "Consider offering difficulty accommodations in games... reduce the criteria for successfully completing a level, adjust reaction time, or enable control assistance." "Use haptics in addition to audio cues." "Augment audio cues with visual cues." Support Dim Flashing Lights. — [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- Increase Contrast: see section 4. Liquid Glass variants "can differ in response to... accessibility settings that reduce transparency or increase contrast." — [HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- Haptics optional: "Let people turn off or mute haptics, and make sure people can still enjoy your app or game without them." — [HIG Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)

### Inferences
- In SwiftUI, read `@Environment(\.accessibilityReduceMotion)`, `\.accessibilityReduceTransparency`, `\.colorSchemeContrast` and `\.accessibilityShowButtonShapes`. Swap glass or blur for solid fills under Reduce Transparency, and add outlines when Button Shapes is on (this follows Apple's general direction, not a game-specific HIG rule). For boards, `accessibilityElement(children:)` with per-cell labels and `accessibilityAction` makes grid puzzles operable with VoiceOver.

### Gaps
- None of the sources reviewed has a dedicated rule for Reduce Transparency or Button Shapes; the Accessibility page fetched does not cover them.
- None of the game sessions reviewed covers VoiceOver for games (WWDC24 10085 and WWDC26 358 do not), and no VoiceOver direct-touch rule for iOS games was found.

## 6. Feedback and motion: animation timing, haptics and audio

### Takeaway
Apple gives no millisecond durations. Its principles are purposeful, brief, precise and cancellable motion, frame rates of 30 to 60 fps, and haptics matched in intensity and sharpness to the animation, used consistently and not overused. Use system haptic types by their documented meanings.

### Cited Findings
- "Add motion purposefully... Gratuitous or excessive animation can distract people." "Aim for brevity and precision in feedback animations." "Let people cancel motion... don't make people wait for an animation to complete." "avoid adding motion to UI interactions that occur frequently." — [HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion)
- "In most games, maintaining a consistent frame rate of 30 to 60 fps typically results in a smooth, visually appealing experience." Let people trade visual quality for battery life. — [HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion)
- Haptics: "Use system-provided haptic patterns according to their documented meanings." "Prefer using haptics to complement other feedback." "In most apps, prefer playing short haptics that complement discrete events" (long-running haptics can suit a gameplay flow). "Use haptics consistently... a clear, causal relationship." "Avoid overusing haptics... the best haptic experience is one that people may not be conscious of, but miss when it's turned off." Match "the intensity and sharpness of a haptic with the intensity and sharpness of the animation it accompanies." — [HIG Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
- iOS generator types: Notification (success, warning, error) for the outcome of a task; Impact (light, medium, heavy, rigid, soft) as a physical metaphor, for example "a tap when a view snaps into place"; Selection "while the values of a UI element are changing." — [HIG Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
- "Games often use custom haptics to enhance gameplay" (Core Haptics transient and continuous events, with optional synced audio). — [HIG Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
- "You can add subtle haptics on touch down and touch up to provide a sense of responsiveness, in addition to designing sound and haptics for the actions that your controls will perform." — [WWDC24 10085](https://developer.apple.com/videos/play/wwdc2024/10085/)

### Inferences
- A suggested mapping, inferred and not specified by Apple:
  - Tile or piece snaps into place: `.impact(.light)` or `.impact(.soft)`.
  - Merge or line clear: `.impact(.medium)`.
  - Level win: `.success`.
  - Game over or invalid move: `.error` or `.warning`, used sparingly.
  - Picker or scroller changes: `.selection`.
- In SwiftUI, use `.sensoryFeedback`, gated by an in-game haptics toggle.

### Gaps
- None of the sources reviewed gives numeric animation durations or curves for iOS. The only numbers are 30 to 60 fps and the visionOS warning about 0.2 Hz oscillation.

## 7. Onboarding / tutorials, pause / interruptions, game over / results, Game Center UI placement

### Takeaway
Onboarding should "teach through play": fast, fun, optional and context-specific, with reasonable defaults and permission or rating requests deferred. Game Center's access point belongs in menus, never during gameplay. Pause while the Game Overlay is visible. Apple has no explicit HIG rule for pause or interruption screens, or for game-over and results screens.

### Cited Findings
- "Teach through play: integrate configuration and onboarding flows into a playable tutorial." Offer a written tutorial "as a resource... instead of making it a prerequisite for gameplay." "Let people play as soon as installation completes." "Defer requests until the right time." Ask for ratings only after people "spend quality time with your game." — [HIG Designing for games](https://developer.apple.com/design/human-interface-guidelines/designing-for-games)
- "if onboarding is necessary, design a flow that's fast, fun, and optional." "Teach through interactivity... safely test an action, discover a feature, or try out a game mechanic." "Consider providing a collection of context-specific tips instead of a single onboarding flow... display these instructions near that area." If a tutorial is skipped, "don't present it again on subsequent launches, but make sure it's easy for people to find." "Postpone nonessential setup flows." Keep splash screens brief. — [HIG Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)
- "Choosing great defaults removes steps, and lets your players start having fun a lot faster." "Aim to get around the first 15 minutes of gameplay bundled into your App Store download." — [WWDC24 10085](https://developer.apple.com/videos/play/wwdc2024/10085/)
- Game Center access point: "Display the access point in menu screens... Avoid displaying the access point during active gameplay or in temporary splash screens, cinematic flows, or tutorials." "Avoid placing controls near the access point." It sits in one of the four corners, in collapsed and expanded forms. — [HIG Game Center](https://developer.apple.com/design/human-interface-guidelines/game-center)
- "Consider pausing your game while the Game Overlay or dashboard is present." — [HIG Game Center](https://developer.apple.com/design/human-interface-guidelines/game-center)
- Game Center terminology: use "Achievements," not "Awards, Trophies, Medals," and "Leaderboards," not "Rankings, Scores, Leaders." Achievement titles and descriptions are limited to two lines each. Achievement art is 512×512 pt with a circular mask. Challenges should "take 1-5 minutes to play" and track the most recent score, not the personal best. — [HIG Game Center](https://developer.apple.com/design/human-interface-guidelines/game-center)
- Multiplayer party codes are "typically eight characters long." "Allow players to join gameplay late, leave early, and return later." — [HIG Game Center](https://developer.apple.com/design/human-interface-guidelines/game-center)
- Menus during play: hide controller UI when the menu shows; menus must respond to touch. — [WWDC24 10085](https://developer.apple.com/videos/play/wwdc2024/10085/)
- GameSave lets people "start back up exactly where they left off on a different device." — [HIG Designing for games](https://developer.apple.com/design/human-interface-guidelines/designing-for-games)
- iOS 26 context: Apple introduced the Apple Games app with iOS 26. — [Apple Newsroom](https://www.apple.com/newsroom/2025/06/apple-elevates-the-iphone-experience-with-ios-26/). The Game Center HIG change log for June 9, 2025 says it added "considerations for the Apple Games app and Game Overlay," but no such text appeared on the page. — [HIG Game Center](https://developer.apple.com/design/human-interface-guidelines/game-center)

### Inferences
- Results and game-over screens should follow the general Buttons rules: one prominent action ("Play again"), secondary actions in a different style, and destructive actions such as "Quit" not primary. Text should be at least 17 pt for the key result, and the Game Center access point and leaderboard links can go on this menu-type screen.
- Auto-pause on `scenePhase` changing to `.inactive` or `.background`, and when the Game Overlay is shown, extends Apple's Game Center pause advice.

### Gaps
- None of the sources reviewed has an explicit rule for pause or resume, or for interruptions such as calls, notifications or backgrounding.
- None of the sources reviewed has an explicit guideline for game-over or results screens.
- None of the sources reviewed specifies Game Overlay behaviour on iOS 26, and the HIG page fetched contains none.
