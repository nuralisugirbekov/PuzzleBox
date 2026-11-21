# Material Design 3 / M3 Expressive, WCAG 2.2, Game Accessibility Guidelines, and NN/g heuristics for casual mobile game UI

Research date: 2026-11-14. Note: m3.material.io is rendered client-side and could not be fetched as text. Material numbers below come from Google's own implementation docs (material-components-android on GitHub, developer.android.com) and Google Design. Values not confirmed in a fetched source are listed under Gaps and marked as unverified.

## 1. Material 3 / M3 Expressive: components, shape, elevation, state, motion, colour

### Takeaway
Use M3's token scales as defaults for a tactile game UI. Shapes run 0/4/8/12/16/20/28/32/48dp plus full. Motion uses springs: spatial springs damp at 0.9 (stiffness 300/700/1400), effects springs at 1.0 (800/1600/3800). Touch targets are 48×48dp with 8dp gaps. Colour pairs are on-X over X. Google's own research found M3 Expressive's larger, bolder, colour-contained key actions are spotted up to 4x faster.

### Cited Findings
**Shape scale (corner radius tokens, M3 + Expressive additions)**
- None 0dp; Extra Small 4dp; Small 8dp; Medium 12dp; Large 16dp; **Large Increased 20dp**; Extra Large 28dp; **Extra Large Increased 32dp**; **Extra Extra Large 48dp**; Full = 50% (pill/circle). Large Increased, Extra Large Increased and Extra Extra Large are the Expressive additions. — [material-components-android Shape.md](https://raw.githubusercontent.com/material-components/material-components-android/master/docs/theming/Shape.md)
- The Compose default `Shapes()` example uses extraLarge = 24dp, while the MDC token is 28dp. This is a small inconsistency between the two Google docs. — [Android Developers: Material 3 in Compose](https://developer.android.com/develop/ui/compose/designsystems/material3)

**Buttons (M3 Expressive "common buttons")**
- There are five sizes: Extra small, Small (the default), Medium, Large and Extra large. The default shape is Corner.Full (round), with a Square variant. Shapes **morph when pressed and when selected**, and toggle buttons "change from round to square when selected". — [MDC CommonButton.md](https://raw.githubusercontent.com/material-components/material-components-android/master/docs/components/CommonButton.md)
- Elevation by style: Elevated **1dp**, Filled **2dp**, Filled tonal **2dp**, Outlined 0dp, Text 0dp. — [MDC CommonButton.md](https://raw.githubusercontent.com/material-components/material-components-android/master/docs/components/CommonButton.md)
- Colour roles (content / container): Elevated = onSurface / surfaceContainerLow; Filled = onPrimary / primary; Tonal = onSecondaryContainer / secondaryContainer; Outlined = onSurface / transparent, with a 1dp stroke in onSurface at 12% opacity. — [MDC CommonButton.md](https://raw.githubusercontent.com/material-components/material-components-android/master/docs/components/CommonButton.md)
- Small button horizontal padding is 16dp ("recommended to match padding of new sizes"; 24dp is deprecated). The icon-to-label gap is 8dp. The ripple uses 16% opacity of the relevant colour role. — [MDC CommonButton.md](https://raw.githubusercontent.com/material-components/material-components-android/master/docs/components/CommonButton.md)
- Emphasis hierarchy, from highest to lowest: Extended FAB → Filled → (Tonal/Elevated/Outlined) → Text button. — [Android Developers: Material 3 in Compose](https://developer.android.com/develop/ui/compose/designsystems/material3)
- Compose card elevation example: default 8dp, pressed 2dp, focused 4dp. In this example a card sinks on press, which is a tactile "press-down" pattern. — [Android Developers: Material 3 in Compose](https://developer.android.com/develop/ui/compose/designsystems/material3)

**Elevation and dark theme**
- M3 shows elevation mainly with **tonal colour overlays** (a higher surface gets a more prominent tone), with shadows added on top. In dark themes the overlay colour comes from primary. `Surface` takes both `tonalElevation` and `shadowElevation`. — [Android Developers: Material 3 in Compose](https://developer.android.com/develop/ui/compose/designsystems/material3)
- Support light and dark themes through `isSystemInDarkTheme()`. Dynamic colour is available on Android 12+ and is "designed to meet accessibility standards for color contrast". — [Android Developers: Material 3 in Compose](https://developer.android.com/develop/ui/compose/designsystems/material3)

**Colour roles and contrast**
- A scheme starts from 5 key colours, each with a tonal palette of 13 tones. Primary is for prominent buttons and active states. Secondary is for less prominent components such as filter chips. Tertiary is for contrasting accents. — [Android Developers: Material 3 in Compose](https://developer.android.com/develop/ui/compose/designsystems/material3)
- Rule: always put onPrimary on primary, onPrimaryContainer on primaryContainer, and so on. Mixing roles, such as primaryContainer text on tertiaryContainer, gives poor contrast. Disabled states may use on-X colours with alpha. — [Android Developers: Material 3 in Compose](https://developer.android.com/develop/ui/compose/designsystems/material3)
- Type scale (size/line height in sp): display 57/64, 45/52, 36/44; headline 32/40, 28/36, 24/32; title 22/28, 16/24, 14/20 (Medium weight); body 16/24, 14/20, 12/16; label 14/20, 12/16, 11/16 (Medium). — [Android Developers: Material 3 in Compose](https://developer.android.com/develop/ui/compose/designsystems/material3)

**Touch targets**
- Touch targets should be at least **48×48dp**, separated by **8dp** or more. The target can extend beyond the visual bounds; for example, a 24dp icon gets padding up to 48dp. — [Google Accessibility Help: Touch target size](https://support.google.com/accessibility/android/answer/7101858?hl=en-GB); repeated with a worked example (24dp icon + 12dp padding per side) in [YouTube Playables design best practices](https://developers.google.com/youtube/gaming/playables/certification/best_practices_design)

**Motion: durations, easing, springs**
- Duration tokens: Short1–4 = 50/100/150/200ms; Medium1–4 = 250/300/350/400ms; Long1–4 = 450/500/550/600ms; ExtraLong1–4 = 700/800/900/1000ms. — [MDC Motion.md](https://raw.githubusercontent.com/material-components/material-components-android/master/docs/theming/Motion.md)
- Easing: Standard cubic-bezier(0.2,0,0,1); Standard decelerate (0,0,0,1); Standard accelerate (0.3,0,1,1); Emphasized is the path "M 0,0 C 0.05,0,0.133333,0.06,0.166666,0.4 C 0.208333,0.82,0.25,1,1,1"; Emphasized decelerate (0.05,0.7,0.1,1); Emphasized accelerate (0.3,0,0.8,0.15); Linear. The same doc also lists a legacy "motionEasingStandard" of (0.4,0,0.2,1) in its transition tables, which is inconsistent with the token list. — [MDC Motion.md](https://raw.githubusercontent.com/material-components/material-components-android/master/docs/theming/Motion.md)
- **Spring tokens** (damping ratio / stiffness): FastSpatial 0.9/1400; DefaultSpatial 0.9/700; SlowSpatial 0.9/300; FastEffects 1.0/3800; DefaultEffects 1.0/1600; SlowEffects 1.0/800. "Spatial" springs (position, size, shape) have slight overshoot. "Effects" springs (colour, opacity) are critically damped, with no bounce. — [MDC Motion.md](https://raw.githubusercontent.com/material-components/material-components-android/master/docs/theming/Motion.md)
- A third-party Flutter package lists the *Expressive* scheme default spatial spring as stiffness **380 / damping 0.8**, which gives more bounce than the standard scheme's 700/0.9. I could not confirm this in a Google primary source. — [pub.dev M3EMotion](https://pub.dev/documentation/m3e_slider/0.0.2/common_m3e_common/M3EMotion-class.html)

**M3 Expressive research (Google)**
- The research covered 46 studies, hundreds of designs and more than 18,000 participants. Users spotted key UI elements **up to 4x faster** in expressive designs; for example, an enlarged Send button was found 4x faster. Tap time on key actions fell "by seconds". Adults aged 45+ spotted key elements about as fast as younger users, so the usual age gap largely disappeared. Expressive was preferred across all ages, most strongly among 18–24 year olds (up to 87%). A "strong minority" preferred calmer versions. — [Google Design: Expressive Material Design research](https://design.google/library/expressive-material-design-google-research)
- The expressive tactics were colour (to highlight key actions and group related ones), bold shape, larger **size** for key actions, high-contrast **containment** grouping, and motion. — [Google Design](https://design.google/library/expressive-material-design-google-research)

### Inferences
- For a "tactile toy" game UI, a reasonable mapping is: primary in-game CTA → Filled or Large/XL button; secondary → Tonal; HUD icon buttons → 48dp hit area even when the glyph is 24dp. Use spatial springs for press/scale and effects springs for colour or opacity changes.
- The Expressive press-morph (round → squarer on press) and the 8dp → 2dp press-sink card example both show that Google endorses physical press feedback, which supports a skeuomorphic or tactile direction.
- The project is an iOS/SwiftUI app. The 48dp target is about 48pt on iOS, which exceeds Apple's 44pt (Apple's figure was not fetched here).

### Gaps
- **State-layer opacities** could not be fetched from m3.material.io. From prior knowledge (unverified this session): hover 8%, focus 10%, pressed 10%, dragged 16%; disabled content 38%, disabled container 12%. Older M3 versions used focus/pressed 12%. MDC's ripple doc says 16%.
- **Exact Expressive button heights** (unverified recollection: XS 32, S 40, M 56, L 96, XL 136dp) and FAB, chip, dialog and bottom-sheet specs were not retrievable. Recollection, unverified: chip height 32dp, dialog corner 28dp, bottom sheet top corners 28dp, FAB 56dp with a 16dp corner, and elevation levels 0/1/3/6/8/12dp. Check these in m3.material.io in a browser.
- I found no primary Google source for the Expressive-scheme spring numbers.

## 2. Google Play / Android guidance for game UI/UX

### Takeaway
Google's games-specific rules are mostly about platform quality, not visuals. The required items are insets for cutouts and system bars, resizability and rotation, full-screen on 4:3/16:10/21:9, controller and keyboard/mouse playability, 60 fps, under 1% crashes and under 2% ANRs, cloud save and achievements. Google's Playables design guide adds concrete UI rules: 48dp targets, 4.5:1 text contrast, clear pause, separate volume sliders and haptics.

### Cited Findings
- **Level Up program** (voluntary; enrolment from Sept 1, 2026). Its themes are a consistent gamer experience, reach across all screens, and stable gameplay. — [Android Developers: Level Up guidelines](https://developer.android.com/games/guidelines)
- **LU-LS-GAA:** use insets so controls and UI don't overlap system bars (status, navigation, gesture) or display cutouts. **LU-LS-GAB:** handle rotation, fold/unfold, multi-window and free resize without crashes, ANRs or visual artifacts. **LU-LS-GAC/GAD:** landscape games render full screen at 4:3, 16:10 and 21:9; portrait games at 3:4, 10:16 and 9:21. — [Android Developers: Level Up guidelines](https://developer.android.com/games/guidelines)
- **LU-IC-GAA:** the game must be fully playable with controller and keyboard/mouse where available. Drag-and-drop and freehand drawing games are exempt from the controller requirement but still need K&M (LU-IC-EAF/EAG). — [Android Developers: Level Up guidelines](https://developer.android.com/games/guidelines)
- **Stability:** under 1% average crash rate and under 2% ANR rate. **LU-PR-GAA:** active gameplay must target at least 60 fps by default on reference devices. — [Android Developers: Level Up guidelines](https://developer.android.com/games/guidelines)
- **Achievements:** at least 10, with 40+ recommended, each with a unique name and description. At least 4 must be achievable in the first hour to be eligible for Quests. **Cloud save** of game state is required, plus a conflict-resolution policy. Games aimed at under-13s are exempt from several of these. — [Android Developers: Level Up guidelines](https://developer.android.com/games/guidelines)
- **Playables (Google/YouTube) UI rules:** 48×48dp targets with 8dp spacing. Buttons need distinct enabled, disabled, hover, focused and pressed states. Close every menu or dialog with Esc and also show a visible close button. Text under 18pt (or bold under 14pt) needs 4.5:1 contrast; other text 3:1. UI must scale from 360×800 to 3840×2560 without blur or stretching. Keep onboarding minimal and contextual. Pause must be clearly labelled "paused" and have a resume button. Celebrate the end of a game. Provide separate volume controls for effects, speech and music. Use haptics where appropriate. Google defers to gameaccessibilityguidelines.com. — [YouTube Playables design best practices](https://developers.google.com/youtube/gaming/playables/certification/best_practices_design)
- The Play Games Services quality checklist says leaderboards should be readily accessible when the game loads, and progress should be backed up to cloud save. — [Quality checklist for Google Play Games Services](https://developer.android.com/games/pgs/quality) (search-snippet level; not fully fetched)

### Inferences
- The iOS equivalents are safe-area insets and the Dynamic Island. HUD elements such as pause and score should be anchored inside the safe area, away from home-indicator gestures.
- The Playables "paused + resume" and "celebrate completion" rules map directly onto the HUD and win-screen work in the redesign roadmap.

### Gaps
- I found no Google document on visual styling for game HUDs specifically (for example, a recommended HUD font size). Apple's HIG "Designing for games" page appeared in search but was not fetched.

## 3. WCAG 2.2 criteria and Game Accessibility Guidelines for casual games

### Takeaway
The criteria that matter most for game UI:
- Contrast: 4.5:1 for text, 3:1 for large text, controls and their state indicators.
- Target size: at least 24×24 CSS px (AA), with 44×44 as the AAA ideal and 48dp as Google's.
- Colour: never use it alone.
- Dragging: offer a tap-to-select alternative to drag (2.5.7, relevant to card and tile games).
- Time limits: adjustable, or exempt as essential or real-time.
- Motion: no flashing above 3 per second, and a way to disable interaction-triggered animation (AAA).
GAG's Basic tier adds large, well-spaced controls, readable default fonts, separate volume sliders, a haptics toggle and adjustable speed or difficulty.

### Cited Findings
**WCAG 2.2 (normative quotes and levels)**
- **1.4.1 Use of Color (A):** "Color is not used as the only visual means of conveying information, indicating an action…" — [WCAG 2.2](https://www.w3.org/TR/WCAG22/)
- **1.4.3 Contrast (Minimum) (AA):** text at least 4.5:1, with an exception for large text at 3:1. Large text is about 18pt regular or 14pt bold; the Playables page restates these thresholds. — [WCAG 2.2](https://www.w3.org/TR/WCAG22/); [Playables](https://developers.google.com/youtube/gaming/playables/certification/best_practices_design)
- **1.4.11 Non-text Contrast (AA):** 3:1 against adjacent colours for the visual information needed to identify a UI component and its **states** (selected, focused), and for meaningful graphical objects. A button boundary is *not* required if the control's text or icon identifies it. If the boundary or fill is the only identifier, it needs 3:1. Disabled controls are exempt. Author hover effects don't need 3:1. The threshold is strict: 2.999:1 fails. Example failure: a #9D9D9D border on white is 2.7:1. — [Understanding 1.4.11](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html)
- **2.5.8 Target Size (Minimum) (AA):** at least 24×24 CSS px. Smaller targets pass if a 24px-diameter circle centred on each one doesn't intersect another target or circle. Other exceptions: an equivalent control elsewhere, inline targets, user-agent controls, and essential presentation. **2.5.5 (AAA)** is 44×44. — [Understanding 2.5.8](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html)
- **2.5.7 Dragging Movements (AA):** "All functionality that uses a dragging movement for operation can be achieved by a single pointer without dragging, unless dragging is essential…". Suggested patterns are tap to select then tap the destination, a move menu, or arrow buttons. The alternative can't rely only on swipes or flicks. — [Understanding 2.5.7](https://www.w3.org/WAI/WCAG22/Understanding/dragging-movements.html)
- **2.5.1 Pointer Gestures (A):** multipoint or path-based gestures need a single-pointer alternative. — [WCAG 2.2](https://www.w3.org/TR/WCAG22/)
- **2.2.1 Timing Adjustable (A):** for each time limit, the user can turn it off, adjust it to at least 10x the default, or extend it with at least 20 seconds' warning and a simple action. Exceptions apply for real-time events, essential limits (where extending would invalidate the activity), and limits over 20 hours. The W3C page doesn't mention games explicitly. — [Understanding 2.2.1](https://www.w3.org/WAI/WCAG22/Understanding/timing-adjustable.html)
- **2.2.2 Pause, Stop, Hide (A):** auto-starting moving, blinking or scrolling content lasting more than 5 seconds must be pausable. **2.3.1 (A):** nothing flashes more than 3 times in any 1-second period, unless below the flash thresholds. **2.3.3 Animation from Interactions (AAA):** motion triggered by interaction can be disabled unless essential. **2.4.11 Focus Not Obscured (AA):** a focused component is not entirely hidden by author content. — [WCAG 2.2](https://www.w3.org/TR/WCAG22/)

**Game Accessibility Guidelines: Basic (verbatim items most relevant to casual touch games)**
- Motor: "Include an option to adjust the game speed"; "Include toggle/slider for any haptics"; "Ensure interactive elements / virtual controls are large and well spaced, particularly on small or touch screens"; "Ensure controls are as simple as possible, or provide a simpler alternative". — [GAG full list](https://gameaccessibilityguidelines.com/full-list/)
- Cognitive: "Avoid flickering images and repetitive patterns"; "Allow players to progress through text prompts at their own pace"; "Include interactive tutorials"; "Use simple clear language"; "Allow the game to be started without the need to navigate through multiple levels of menus"; "Use an easily readable default font size". — [GAG full list](https://gameaccessibilityguidelines.com/full-list/)
- Vision: "Provide high contrast between text/UI and background"; "Ensure no essential information is conveyed by a fixed colour alone". Hearing: "Ensure no essential information is conveyed by sounds alone"; "Provide separate volume controls or mutes for effects, speech and background / music". General: "Ensure that all settings are saved/remembered"; "Offer a wide choice of difficulty levels". — [GAG full list](https://gameaccessibilityguidelines.com/full-list/)
- Intermediate items relevant here: "Give a clear indication that interactive elements are interactive"; "Make interactive elements that require accuracy … stationary"; "Include a means of practicing without failure"; "Provide an autosave feature"; "Indicate / allow reminder of current objectives during gameplay"; "Include contextual in-game help / guidance / tips"; "Allow difficulty level to be altered during gameplay"; "Provide an option to adjust contrast". — [GAG full list](https://gameaccessibilityguidelines.com/full-list/)

### Inferences
- Card games such as Solitaire, FreeCell, Spider and Durak, and tile games such as 2048 and Blocks, should offer tap-to-select then tap-to-place alongside drag, to satisfy 2.5.7. Swipe-only 2048 controls would need a non-path alternative to fully meet 2.5.1/2.5.7, though a game could argue the "essential" exception.
- Under 1.4.11, the shape and colour that tell a "pressed/selected" tile from an idle one need 3:1 against neighbours. Card suits and colour-coded pieces need a shape or symbol as well as colour (1.4.1 and GAG).
- Honour iOS Reduce Motion, which covers 2.3.3 for bouncy spring effects. Celebration effects must stay under 3 flashes per second.

### Gaps
- WCAG is written for web content. W3C's WCAG2ICT guidance on applying it to native apps was not fetched. How the "essential" exception applies to game timers is a matter of interpretation.
- GAG has no numeric font-size or target-size values; it defers to platform minimums.

## 4. NN/g-style usability heuristics applied to mobile games: status, consistency, error prevention, recognition, hierarchy, signifiers, skeuomorphism vs flat

### Takeaway
Nielsen's 10 heuristics (last reviewed Jan 2024) still apply. For games the most relevant are visibility of status (score, moves, timer, turn), user control (undo, pause), error prevention (confirm before abandoning a game), and recognition over recall (show the goal). NN/g's eyetracking evidence says weak, flat signifiers cost about 22% more time and 25% more fixations. Strong, button-like signifiers, used moderately and with enough contrast (not low-contrast neumorphism), are the evidence-backed choice.

### Cited Findings
- The 10 heuristics: visibility of system status; match with the real world; user control and freedom (undo/exit); consistency and standards; error prevention (constraints, defaults, confirmation); recognition rather than recall; flexibility and efficiency; aesthetic and minimalist design; help users recognise, diagnose and recover from errors; help and documentation (in context). Originally published 1994, last reviewed Jan 30, 2024. — [NN/g: 10 Usability Heuristics](https://www.nngroup.com/articles/ten-usability-heuristics/)
- **Flat UI study:** 71 users, eyetracking, 9 page pairs that differed only in signifier strength. Weak signifiers meant **about 22% longer** task time and **about 25% more fixations** (both significant). In one pair, 86% of strong-version users went straight to the target versus 50% on the weak version, and some weak-version users stopped on non-clickable subheadings they assumed were clickable. — [NN/g: Flat UI Elements Attract Less Attention and Cause Uncertainty](https://www.nngroup.com/articles/flat-ui-less-attention-cause-uncertainty/)
- NN/g recommendations: give clickable elements strong signifiers (visibly button-like controls, contrasting colour). Flat works only with low information density, conventional layouts, and high-contrast, well-spaced targets. Use strong signifiers for features users don't know exist. — [NN/g flat UI study](https://www.nngroup.com/articles/flat-ui-less-attention-cause-uncertainty/)
- Skeuomorphism helps users learn through familiar metaphors, but as a decorative trend it added clutter. Flat design removed cues and created "weak signifiers". Neumorphism's subtle embossing failed to go mainstream because its low contrast hurts accessibility and makes clickable elements hard to identify. NN/g advises balancing "innovation and familiarity". — [NN/g: Skeuomorphism](https://www.nngroup.com/articles/skeuomorphism/)
- Google's Expressive research supports this: larger, contained, higher-contrast key actions are found up to 4x faster. — [Google Design](https://design.google/library/expressive-material-design-google-research)
- GAG Intermediate: "Give a clear indication that interactive elements are interactive." — [GAG full list](https://gameaccessibilityguidelines.com/full-list/)

### Inferences
- Tactile-toy styling is supported if it carries real signifiers: depth or shadow, a press-down state, and contrasting fill. It is also important that non-interactive decoration (board backgrounds, score plates) does *not* look pressable, or the false-affordance problem from the NN/g study reappears.
- Consistency vs distinctiveness: keep the HUD controls (pause, undo, hint, restart) in the same position, shape and icon set across all games, which follows heuristic 4. Express each game's personality through its board and pieces, not through different control idioms.
- Error prevention in games means confirming Restart/Quit when progress would be lost, offering undo where the rules allow (heuristic 3), and showing legal-move hints on selection.

### Gaps
- I found no NN/g or Baymard article specific to mobile *game* UI. Baymard covers e-commerce and was not relevant. All game applications above are inferences from general heuristics.
- The NN/g flat-UI study was run on desktop web pages, not mobile games, so applying it to touch games is an extrapolation.
