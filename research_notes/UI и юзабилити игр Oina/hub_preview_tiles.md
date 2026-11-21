# Game hub preview tiles: composition, art vs. text, colour, motion, badges, accessibility

Research date: 2026-11-14. Scope: how multi-game hubs present each game in a tile, and what makes a 100–170 pt tile readable and inviting. Context: Oina Home grid of ~35 mini-game tiles to be restyled to match each game's colour world and tactile "3D toy" in-game art.

Source quality note: the most detailed, prescriptive sources are platform submission guidelines (Poki, CrazyGames) and Apple HIG. Public design write-ups on how Apple Arcade, Netflix Games, GamePigeon, Google Play Games, Clubhouse Games and Microsoft Solitaire Collection lay out their tiles are thin. Most coverage is press or fan-wiki material describing features, not visual specs. Gaps are marked explicitly.

## How do major game hubs present each game in a tile?

### Takeaway
Web portals (Poki, CrazyGames) are the most explicit. They want one hero subject on full-bleed square art, strong contrast, no clutter and no screenshots. They disagree on whether the title belongs on the art. NYT Games is the closest analogue to Oina (a first-party hub of small daily games): it uses per-game "game cards" with bold colour and clear brand icons, and the same card shows progress once you have started. Apple's Games app and Microsoft Solitaire Collection centre on hub/launcher structure plus daily or social hooks. I found no reliable public spec for their tile art.

### Cited Findings
**Poki (web portal, square tiles shown at many sizes)**
- Use one clear foreground object, "a main character or a key gameplay element, not a collage of everything". Keep the background simple and clean. — [Poki for Developers: Thumbnail](https://developers.poki.com/guide/thumbnail)
- The visuals should closely match the actual game ("show what's inside"). Suggest motion with a dynamic pose rather than a stiff one. — [Poki: Thumbnail](https://developers.poki.com/guide/thumbnail)
- Games in a series should have recognisably related thumbnails. — [Poki: Thumbnail](https://developers.poki.com/guide/thumbnail)
- Avoid titles and other text, because text becomes unreadable on smaller tiles. Poki's tests found players prefer text-free thumbnails and that "visuals alone drive better performance". — [Poki: Thumbnail](https://developers.poki.com/guide/thumbnail)
- Use strong contrast, since similar shades "fall flat". Avoid colours close to the portal's own background (#83FFE7), or the tile blends into the page. — [Poki: Thumbnail](https://developers.poki.com/guide/thumbnail)
- Art is a full-bleed 1:1 square of at least 628x628 px with no padding, borders or letterboxing. The platform applies the rounded corners. Check the art at both large and small sizes, because heavy detail "turns to mush when small". — [Poki: Thumbnail](https://developers.poki.com/guide/thumbnail)

**CrazyGames (web portal, landscape/portrait/square covers)**
- "Keep it simple!" Over-cluttered covers are hard to scan, especially on small screens. — [CrazyGames docs: Game covers](https://docs.crazygames.com/requirements/game-covers/)
- "Don't just take a screenshot of the game." Covers can be artistic and "don't have to be an accurate representation of the gameplay". The main character is suggested as the primary visual element. — [CrazyGames: Game covers](https://docs.crazygames.com/requirements/game-covers/)
- Unlike Poki, CrazyGames wants the game's name on the cover in a stylised font that fits the game. No other words are allowed ("New", "Updated", "Play", "Play now"), and no icons, store logos or borders. — [CrazyGames: Game covers](https://docs.crazygames.com/requirements/game-covers/)
- Use consistent visuals across the three cover formats (16:9 1920x1080, 2:3 800x1200, 1:1 800x800), so the game is recognisable in any slot. — [CrazyGames: Game covers](https://docs.crazygames.com/requirements/game-covers/)
- The cover is described as the game's "storefront". — [CrazyGames docs (via search)](https://docs.crazygames.com/general/game-covers/)

**NYT Games (first-party hub of daily puzzles: Wordle, Connections, Mini, Spelling Bee, Strands…)**
- The redesign centres on new "game cards". Before you play, the cards help discovery. After you start, they show progress (which games you've played, how far along you are), meant to make players come back and finish. — [TechCrunch, 7 Mar 2024](https://techcrunch.com/?p=2675705)
- The team "used a lot of color" to show new players the range of games. "The brand icons are very clear and we streamlined the typography." Returning players get a more functional feel. — [TechCrunch](https://techcrunch.com/?p=2675705)
- All games, archives and packs sit in one vertical list instead of a horizontal scroll. Tabs went from five to three (Games, Stats, Leaderboard). Personalised greetings change by time of day. — [TechCrunch](https://techcrunch.com/?p=2675705)
- NYT's announcement says the cards reflect progress on Spelling Bee, Wordle, The Crossword and The Mini, and surface past puzzles and archives directly in the feed. — [CityBiz reprint of NYT announcement](https://www.citybiz.co/?p=529342); [TechEdt](https://www.techedt.com/nyt-games-unveils-redesigned-app-for-enhanced-discovery-and-easier-navigation)
- Dates conflict. TechCrunch dates the redesign coverage 7 March 2024, while TechEdt's page is dated 31 July 2025. The July 2025 page may be a later reprint or a second iteration; I could not confirm which. — [TechCrunch](https://techcrunch.com/?p=2675705) vs [TechEdt](https://www.techedt.com/nyt-games-unveils-redesigned-app-for-enhanced-discovery-and-easier-navigation)
- NYT Games builds shared design systems and reusable components so the visual language stays coherent across puzzles. Wordle stays "almost radically minimal", and Connections is "a remarkably approachable grid of coloured tiles" (summary of Creative Review via search snippet; the page itself returned 403). — [Creative Review](https://www.creativereview.co.uk/new-york-times-games-wordle-crossplay-design-jonathan-knight/)
- Commentary (secondary source): each game is instantly recognisable by its core motif (Wordle's coloured tiles, Spelling Bee's honeycomb, Connections' grouped categories) inside a shared visual language. — [GeekChamp](https://geekchamp.com/?p=791907)

**Apple Games app (iOS 26) / Apple Arcade**
- The Games app (2025) has Library and Play Together tabs. Library entries show last-played time and a launch/download option. Play Together shows what friends are playing plus asynchronous Challenges. — [MacRumors guide](https://www.macrumors.com/guide/ios-26-games-app/); [Apple Newsroom](https://www.apple.com/at/newsroom/2025/06/introducing-the-apple-games-app-a-personalized-home-for-games)
- A game's page in the Games app pulls the App Store product page metadata (description, screenshots, previews). — [Apple Developer: Introducing the Apple Games app](https://developer.apple.com/games-app/index.html)
- Apple TV app (March 2026) analogue: in large-artwork rows, a video preview autoplays only after the user pauses on a title long enough, not while scrolling. — [9to5Mac, 19 Mar 2026](https://9to5mac.com/2026/03/19/apples-tv-app-just-added-autoplaying-video-to-more-parts-of-the-app)

**Clubhouse Games: 51 Worldwide Classics (Nintendo)**
- The main menu is a globe with small figurine "Game Guides". You pick a guide, who takes you to their suggested games and gives trivia and history. Reviewers found this cute but awkward (you must invite a guide before playing; not every category maps to a place). — [Wikipedia](https://en.wikipedia.org/wiki/Clubhouse_Games:_51_Worldwide_Classics); [TV Tropes](https://tvtropes.org/pmwiki/pmwiki.php/Videogame/ClubhouseGames); [Nintendo World Report preview](https://nintendoworldreport.com/preview/53795)
- In Free Play you can pick any of the 52 games, and each game has a step-by-step rules intro. — [GamePressure](https://gamepressure.com/games/51-worldwide-games/ze5c2d); [VGC review](https://www.videogameschronicle.com/review/51-worldwide-games-clubhouse/)

**Microsoft Solitaire Collection**
- The hub design was inspired by the Windows 8 Start screen (2012). It is a tile hub for five games (Klondike, Spider, FreeCell, TriPeaks, Pyramid) plus a Daily Challenges entry with a calendar and one challenge per game per day. — [Wikipedia](https://en.wikipedia.org/wiki/Microsoft_Solitaire_Collection)

**Netflix Games / GamePigeon**
- Netflix shows games as a "Mobile Games" row on the home screen plus a Games shortcut. You tap a game's icon in the row to install or open it. No visual spec was found. — [Netflix Help](https://help.netflix.com/en/node/121442); [Netflix announcement 2021](https://about.netflix.com/en/news/let-the-games-begin-a-new-way-to-experience-entertainment-on-mobile)
- GamePigeon presents a scrollable grid of game icons in the iMessage app drawer, and picking one sends a message bubble. No design write-up was found. — [iGeeksBlog Gomoku guide](https://www.igeeksblog.com/how-to-play-gomoku-on-imessage/); [App Store listing](https://apps.apple.com/za/app/gamepigeon/id1124197642)

### Inferences
- For a fixed catalogue of ~35 first-party games with no competing third-party art, NYT's model fits Oina best: a strong per-game colour plus one clear brand motif, with the same tile becoming a progress card after first play.
- On the title question (Poki says no text on the art, CrazyGames says the title on the art), the iOS-native answer is to keep the art text-free and put the title as a real text label under or inside the tile. That localises (Oina ships 8 languages), scales with Dynamic Type and is read by VoiceOver.
- Clubhouse Games shows the risk of an overly metaphorical hub: charm that adds steps before play. Tiles should open the game in one tap.
- Both Poki and CrazyGames reject "just a screenshot". For Oina, the tile should show the game's hero toy object (for example the 2048 tile block, Helix Drop tower, Battleship ship), not a miniature of the live board with HUD.

### Gaps
- No primary source describes Apple Arcade, Google Play Games, Netflix Games, GamePigeon or Puzzle Page tile composition (art size, title placement, per-game background colour). Inspecting the apps or Mobbin/Game UI Database screenshots would be needed, and those sites were not reachable in this pass.
- NYT Games' exact per-game colours and icon construction rules are not publicly documented in sources found.
- No data was found on which badge types ("new", "daily", streak) lift engagement in hub grids.

## What makes a thumbnail readable at ~100–170 pt?

### Takeaway
The sources agree: one centred hero object, a simple solid or gradient background, a limited palette with strong figure-ground contrast, bold filled shapes with no thin lines or fine detail, no tiny UI or text, and one rendering style with the same lighting and perspective across the whole set. Each tile should also differ from its neighbours by silhouette, not only by hue.

### Cited Findings
- "Find a concept or element that captures the essence of your app or game… and express it in a simple, unique way with a minimal number of shapes." — [Apple HIG: App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- "Prefer a simple background, such as a solid color or gradient, that puts the emphasis on your primary design." "Consider basing your icon design around filled, overlapping shapes." — [Apple HIG: App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- "Avoid extremely thin line weights and sharp corners, because they tend to lose detail and crispness in smaller icon sizes." Fine features make an icon look busy, and detail is hard to discern when small. — [Apple HIG: App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- "Keep primary content centered to avoid truncation when the system adjusts corners or applies masking." — [Apple HIG: App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- "Don't just replicate standard UI components or use app screenshots in your icon." "Prefer illustrations to photos." — [Apple HIG: App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- "Design a background that both stands out and emphasizes foreground content", full-bleed and opaque. "Prefer clearly defined edges in foreground layers" (no soft or feathered edges). — [Apple HIG: App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- Do the silhouette test: fill each icon solid black and check the set is still distinguishable. Differentiate by shape first, with colour and detail as secondary cues. — [Made Good Designs: Game icon design](https://madegooddesigns.com/?p=5494)
- "High contrast, bold shapes, limited palette." A set "distinguished only by hue fails colorblind players". — [Made Good Designs](https://madegooddesigns.com/?p=5494)
- Use one rendering style across the set (same line weight, detail level, perspective and "same lighting direction"), on a common grid with the same optical padding. Mixing flat and rendered icons "looks amateur". — [Made Good Designs](https://madegooddesigns.com/?p=5494)
- "Design at the largest required size, judge at the smallest," previewed over the real UI background. — [Made Good Designs](https://madegooddesigns.com/?p=5494)
- Poki's equivalent rules: one foreground object, simple background, strong contrast, contrast against the page background, and check at small sizes. — [Poki: Thumbnail](https://developers.poki.com/guide/thumbnail)

### Inferences
- For Oina's 3D-toy style: set one global key light (for example top-left) and one camera angle (for example a slight 3/4 top-down) for every tile's hero object, so a grid of 35 different colour worlds still reads as one family. This mirrors Apple's guidance to let the system supply highlights rather than baking in per-icon effects.
- Let the colour world appear as a full-bleed tile background (gradient or solid in the game's hue) with the hero object filling about 55–70% of the tile, centred, and enough margin for corner rounding and badges. The percentage is a design judgement, not a sourced figure.
- Adjacent-tile contrast: with ~35 hues some neighbours will clash or merge. Alternate light and dark values in grid order, and make sure silhouettes differ (round versus tall versus flat objects).
- At 100 pt, avoid boards with many cells (Sudoku grids, card tableaus). Use one emblematic object instead: a single card fan, a single chess piece, one arrow.

### Gaps
- No quantitative study was found on the optimal hero-object fill ratio or minimum feature size in points for game tiles.

## Animated / live tiles: when do they help, and what about battery and Reduce Motion?

### Takeaway
Portals use motion only on intent (hover, or a pause in scrolling). Apple TV autoplays only after the user stops on a title. Apple HIG warns against gratuitous, repeated motion in frequent UI and requires respecting Reduce Motion and autoplay preferences. For a grid of 35 tiles, the static tile is the default. Motion should be a brief, single, purposeful accent (on press, on a newly unlocked game, or on a "today's puzzle" tile), not continuous loops.

### Cited Findings
- Poki animated thumbnails run 4–6 s (2–3 scenes of 1–2 s), play when players hover over the static thumbnail, focus on core mechanics, hide non-essential UI, keep action centred for the square crop, start from the static art, and are muted. — [Poki: Your game page](https://developers.poki.com/guide/your-game-page)
- CrazyGames preview videos are at most 15–20 s, with no sound and no "Play Now" text, and use the static cover as the opening frame for a seamless transition. — [CrazyGames: Game covers](https://docs.crazygames.com/requirements/game-covers/)
- Apple TV app: a preview autoplays only when you pause on a title, not while scrolling. — [9to5Mac](https://9to5mac.com/2026/03/19/apples-tv-app-just-added-autoplaying-video-to-more-parts-of-the-app)
- "Don't add motion for the sake of adding motion. Gratuitous or excessive animation can distract people and may make them feel disconnected or physically uncomfortable." "In apps, generally avoid adding motion to UI interactions that occur frequently." — [Apple HIG: Motion](https://developer.apple.com/design/human-interface-guidelines/motion)
- "Make motion optional… avoid using it as the only way to communicate important information." "Let people customize the visual experience of your game to optimize performance or battery life." — [Apple HIG: Motion](https://developer.apple.com/design/human-interface-guidelines/motion)
- With Reduce Motion on, apps should reduce "automatic and repetitive animations, including zooming, scaling, and peripheral motion". Replace x/y/z transitions with fades, avoid animating depth (z-axis) changes and blurs, and tighten springs. — [Apple HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- "Avoid autoplaying audio and video content without also providing controls to start and stop it." Respect the system autoplay setting (`UIAccessibility.isVideoAutoplayEnabled`) and Dim Flashing Lights. — [Apple HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

### Inferences
- Touch has no hover, so Poki's hover trigger maps on iOS to press state (a tactile squash or tilt of the 3D toy on touch-down) and to one-shot "attention" animations for genuinely new state (new game, daily puzzle ready).
- Rendering 35 live SwiftUI/SceneKit scenes in a scrolling grid costs battery and frame rate. Use pre-rendered static images (or a static SwiftUI drawing) for tiles, with at most one subtle idle animation at a time. Disable idle animations under Reduce Motion and Low Power Mode (`ProcessInfo.isLowPowerModeEnabled`, an inference from standard iOS APIs not covered by the sources above).

### Gaps
- No published battery measurements were found for animated grid tiles on iOS.
- No A/B data was found on whether animated tiles raise taps in mobile game hubs (Poki makes animated thumbnails mandatory, which implies it values them, but publishes no numbers).

## Accessibility: text labels, contrast, VoiceOver

### Takeaway
Use real text titles (not baked into the art) that meet WCAG AA contrast against the tile colour and scale with Dynamic Type. Give each tile a single VoiceOver element with name plus state. Never use colour alone for state, so badges need a shape or icon and text. Keep a tap target well above 44x44 pt (tiles easily satisfy this).

### Cited Findings
- Contrast follows WCAG AA: 4.5:1 for text up to 17 pt, and 3:1 for 18 pt or larger or bold text. Check both light and dark appearances, and offer higher contrast when Increase Contrast is on. — [Apple HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- Minimum iOS control size: 44x44 pt by default, 28x28 pt minimum. Spacing around elements should be about 12 pt with a bezel or 24 pt without. — [Apple HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- "Convey information with more than color alone… Offer visual indicators, like distinct shapes or icons." Red-green and blue-orange pairings are hard for colour-blind people. — [Apple HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- Support Dynamic Type, ideally up to 200%. The iOS minimum text size is 11 pt (17 pt default). — [Apple HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- "Describe your app's interface and content for VoiceOver", and label elements for Voice Control. — [Apple HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- Text in icons "doesn't support accessibility or localization, is often too small to read easily, and can make an icon appear cluttered." — [Apple HIG: App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)

### Inferences
- Suggested VoiceOver pattern (SwiftUI): `.accessibilityElement(children: .combine)` on the tile, with label "2048", value "New" or "Best 4096" or "Daily puzzle not played", and the `.isButton` trait. The hero art is decorative (`.accessibilityHidden(true)`).
- Placing the title on a bright game hue (yellow, mint) often fails 4.5:1 with white text. Use dark text on light hues, or put the title on a neutral label strip or plate below the art.
- At large Dynamic Type sizes, let titles wrap to two lines or move below the art rather than truncating.

### Gaps
- No source specifically on VoiceOver patterns for game-hub grids was found. The pattern above is standard SwiftUI practice, not a cited guideline.

## App icon principles (Apple HIG) that transfer to tiles; state badges

### Takeaway
Most HIG app-icon rules carry straight over to tiles: one essence-capturing concept, minimal filled shapes, a simple full-bleed background, centred content, no screenshots or UI replicas, no text in the art (and no "New" or "Play" baked in), a consistent design across appearances, and system-style lighting rather than custom baked effects. Badges and state should therefore be separate UI layers drawn by the app, not painted into the art.

### Cited Findings
- "Embrace simplicity in your icon design." — [Apple HIG: App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- "Let the system handle blurring and other visual effects." Don't add "specular highlights, drop shadows between layers, beveled edges, blurs, glows". In iOS 26 Liquid Glass, foreground layers get system specular highlights, refraction and translucency. — [Apple HIG: App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- "Vary opacity in foreground layers to increase the sense of depth and liveliness." Provide layered, unmasked art (Icon Composer). — [Apple HIG: App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- Avoid action words like "Watch" or "Play" and context terms like "New" in icons. — [Apple HIG: App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- "Keep your icon's features consistent across appearances." Base dark variants on the light one. "Color backgrounds generally offer the greatest contrast in dark icons." — [Apple HIG: App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- "A great app icon is visible, legible, and recognizable, regardless of its appearance variant." — [Apple HIG: App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- CrazyGames also bans "New", "Updated" and "Play now" text on covers. — [CrazyGames: Game covers](https://docs.crazygames.com/requirements/game-covers/)
- NYT game cards carry state (progress, played or not) on the card itself after first play. — [TechCrunch](https://techcrunch.com/?p=2675705)
- Microsoft Solitaire Collection exposes "daily" as a dedicated hub entry with a calendar, one challenge per game per day. — [Wikipedia](https://en.wikipedia.org/wiki/Microsoft_Solitaire_Collection)
- The Apple Games app shows last-played time and friends' activity on library entries. — [MacRumors](https://www.macrumors.com/guide/ios-26-games-app/)

### Inferences
- Separate art and state: hero art as a static asset or layer, with badges as small app-drawn overlays in a fixed corner. Use at most one badge per tile, ranked for example Daily ready > New > Progress/Best > Multiplayer. Each badge combines an icon and a short word (not colour alone), and badge positions stay consistent across all 35 tiles.
- A visible "Play" button on each tile is redundant: the whole tile is the button, and both Apple HIG and CrazyGames discourage "Play" text in art.
- For the 3D-toy look, either bake the lighting consistently across all assets or render the toys with one shared SwiftUI light model. Either way, keep a single light direction for the whole grid.
- Dark mode: keep each game's hue as the tile background (HIG says colour backgrounds give the best contrast in dark icons), perhaps slightly deeper, rather than switching to black tiles.

### Gaps
- No sourced evidence was found on the optimal number of badges per tile or on badge placement conventions in specific apps (Apple Arcade "New" labels, Google Play Games, Puzzle Page).
