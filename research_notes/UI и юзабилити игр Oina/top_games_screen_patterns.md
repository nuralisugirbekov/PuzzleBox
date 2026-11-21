# How top casual and puzzle mobile games structure the in-game screen and flow

Note on evidence quality: the web search turned up few pixel-level HUD teardowns. Most UI galleries (Game UI Database, Mobbin, Lazyweb) are image-based and can't be read as text, and several articles (Medium/Supercent, gamedev.net, Creative Review) returned 403. Facts below carry inline sources. Anything marked "(unverified, from general knowledge)" in the Inferences sections is the researcher's own recollection of the games and should be checked against screenshots before it is relied on.

## 1. Per-game HUD layout and hierarchy (what is biggest, where goal/moves/stars/timer/pause sit, chrome vs board)

### Takeaway
None of the reference games uses a universal skeleton. Two families recur. (a) Level-based "goal + moves" games (Candy Crush, Royal Match, Two Dots) put a compact goal/moves panel at the top and give the rest of the screen to the board. (b) Score-chasers and hyper-casual games (Flappy, Stack, Helix Jump, Threes, Mini Metro) show one number, or tuck the information into a corner or into the scene. In both families the board or scene is by far the biggest element.

### Cited Findings
- **Candy Crush Saga:** the level target "will be shown on a counter at the top of the screen". A pre-level "level goals" screen shows the target and lets you add boosters — [King help: game modes](https://community.king.com/en/candy-crush-saga/kb/articles/459-which-game-modes-will-i-find)
- **Candy Crush:** the fan wiki puts the target score top-right and boosters top-left, with moves/time at the bottom. This conflicts with King's description and may describe an older layout. The move counter blinks when 5 moves remain — [Candy Crush wiki](https://candycrush.fandom.com/wiki/Points); [King help](https://community.king.com/en/candy-crush-saga/kb/articles/459-which-game-modes-will-i-find)
- **Royal Match:** goal objectives appear at the top of the screen, and players check remaining moves against the goal — [Gamezebo strategy guide](https://www.gamezebo.com/2021/04/22/royal-match-strategy-guide-top-5-best-hints-tips-and-cheats/) (summarised via search snippet)
- **Royal Match:** pieces are larger than in most switcher games, with saturated colours and distinct shapes for fast scanning. Contrast between background, board and pieces is tuned finely ("a small change in grey" is noticeable). Production obstacles show when to stop matching next to them, so the player doesn't have to count — [Deconstructor of Fun, Royal Match](https://www.deconstructoroffun.com/blog/2021/3/21/royal-match-the-new-king-from-turkey)
- **Two Dots:** objectives are concrete counts (e.g. 50 red, 50 blue, 50 yellow dots within 30 moves) shown at the start of each level. Three stars come from finishing with moves to spare, plus a numeric score — [TouchArcade review](https://toucharcade.com/2014/06/23/twodots-review/); [TechCrunch](https://techcrunch.com/2014/05/31/two-dots-the-sequel-to-betaworks-dots-is-a-beautiful-monster/); [Wikipedia](https://en.wikipedia.org/wiki/Two_Dots_(video_game))
- **Threes!:** the only extra HUD element is a "next tile" preview above the board. It shows the type/colour of the next tile, not its number, a deliberate design limit that blocks a corner strategy. Monster faces sit at the bottom of each tile so the number stays dominant — [Wired, "Design is why 2048 sucks…"](https://hn.jakechampion.name/reader/http://www.wired.com/2014/05/threes-game-design); [Yahoo beginner's guide](https://tech.yahoo.com/general/article/a-beginners-guide-to-threes-the-numbers-game-you-77080683484.html)
- **Mini Metro:** the clock, calendar and score sit "tidy and out of the way in the top right corner" as supplementary information. The clock changes colour for day/night. The whole UI follows transit-map styling — [Mechanics of Magic, Visual design of Mini Metro](https://mechanicsofmagic.com/2023/04/22/visual-design-of-games-mini-metro/); [Wikipedia](https://en.wikipedia.org/wiki/Mini_Metro_(video_game))
- **Monument Valley:** "almost entirely 3D" with a minimal UI system. Dialogue and interactions are "purposefully minimal" and personality comes through animated details — [Unity case study](https://activation.unity3d.com/case-study/monument-valley); [TechCrunch review](https://techcrunch.com/?p=977064)
- **Flappy Bird:** the whole UI is a start button, a score, and the game parts — [Pixune hypercasual UI guide](https://pixune.com/blog/hypercasual-games-ui-ux-design-guide/)
- **Helix Jump:** the in-game HUD shows the level display and score counter with the tower. The main menu has only three options (Play, Shop, Settings) — [Pixune](https://pixune.com/blog/hypercasual-games-ui-ux-design-guide/)
- **Stack:** smaller platforms higher up signal rising difficulty, a progression cue in the scene rather than in the HUD. Haptics mark a new high score — [Pixune](https://pixune.com/blog/hypercasual-games-ui-ux-design-guide/)
- **Hole.io:** the timer creates pressure and the hole visibly grows as it eats objects, so progress shows in the scene — [Pixune](https://pixune.com/blog/hypercasual-games-ui-ux-design-guide/)
- **Color Switch:** the colour wheel is both a menu element and an in-game obstacle, blurring UI and gameplay — [Pixune](https://pixune.com/blog/hypercasual-games-ui-ux-design-guide/)
- **Block Blast:** an 8×8 board (some sources say 9×9) with a tray of three pieces at the bottom. The tray refills only after all three are placed, and there is no rotation. Reviewers note its "minimalist aesthetic" — [Astana Hub article](https://astanahub.com/en/blog/block-blast-the-addictive-puzzle-game); [cinevva spec](https://app.cinevva.com/arcade/block-blast). Score/crown placement unverified.
- **Microsoft Solitaire Collection:** the modern app replaced drop-down menus with a hamburger menu, and Hint and Undo buttons sit at the bottom of the game screen. It has score, time and moves counters, but no source confirmed where they sit — [Wikipedia mirror](https://bafybeiemxf5abjwjbikoz4mc3a3dla6ual3jsgpdr4cjr3oz3evfyavhwq.ipfs.4everland.io/wiki/Microsoft_Solitaire_Collection.html); [Microsoft Store](https://microsoft.com/store/productId/9WZDNCRDNB1Z)
- **Good Sudoku:** reviewers praise its focused look, strong haptics and smooth transitions. One App Store reviewer found it confusing that there are "three different tools just for the note function". Hand-holding aids can be turned off in settings — [MacStories](https://www.macstories.net/reviews/game-day-good-sudoku/); [TouchArcade](https://toucharcade.com/games/good-sudoku-by-zach-gage); [App Store](https://apps.apple.com/app/id1551669399)
- **NYT Games app:** redesigned from a crossword-centric app into a hub. It went from five bottom tabs to three (Games, Stats, Leaderboard) after testing tab configurations (Jennifer Scheerer, Lian Chang) — [TechCrunch](https://techcrunch.com/?p=2675705); [Techedt](https://www.techedt.com/nyt-games-unveils-redesigned-app-for-enhanced-discovery-and-easier-navigation)
- **Fortnite mobile (general HUD guidance):** show no more than 5–6 active controls at once, and give the primary action prominence — [Epic docs](https://dev.epicgames.com/documentation/fortnite/designing-for-mobile-in-fortnite)

### Inferences
- The level-based games (Candy Crush, Royal Match, Two Dots) share a pattern: one top panel that combines goal icons with remaining counts, plus a large moves number. Stars are not shown live, or only as a thin bar, and appear on the result screen. Oina's separate pill chips for level, moves and stars break this into too many equal-weight items.
- Score-chasers (Threes, Flappy, Stack, Helix) make the score the only HUD element, or move the "next/progress" information into the board itself (Threes' next tile, Stack's shrinking slab, Hole.io's growing hole). This argues for removing the universal debossed clock from games where a clock means nothing.
- (Unverified, from general knowledge) In Wordle and Connections the board sits in the upper-middle and the interaction surface (keyboard; Shuffle/Deselect/Submit buttons and the mistakes-remaining dots) sits at the bottom. There is no score, and the Mini crossword's timer is small. Each NYT game has its own colour identity, while the top bar is shared and thin (back, title, help/settings icons).
- (Unverified) In Water Sort, Flow Free and Unblock Me the level number is small at the top, a few utility icons (restart, undo, hint) sit in a bottom row, and the board fills the middle. Flow Free shows "flows / moves / pipe %" as small text above the board.
- (Unverified) In Chess.com Puzzles the board sits in the upper-middle, a "White/Black to move" prompt sits above or below it, and hint, retry and next buttons sit in a bottom bar.
- (Unverified) In Helix Jump a thin level-progress bar sits at the top (current level → next level) with the score under it. Stack and Knife Hit show only a large score number in the top centre. Knife Hit adds remaining-knife icons down the left side and the stage dots at the top.

### Gaps
- No text source gave verified layouts for Alto's Odyssey, Gardenscapes, Water Sort, Flow Free, Unblock Me, Suika, Knife Hit, Crossy Road, slither.io, Chess.com puzzles or the NYT games' own screens. Screenshot galleries (gameuidatabase.com, mobbin, Lazyweb [Royal Match page](https://app.lazyweb.com/company/royal-match)) hold this but can't be read as text. Checking them visually is recommended.
- No current (2025–2026) Royal Match or Candy Crush HUD teardown was found.

## 2. Layouts that grow from the mechanic (score inside the scene, goal in the board frame, controls at thumb reach)

### Takeaway
The strongest references show state through the mechanic itself rather than through generic chips. Examples: the next tile in Threes, the shrinking slab in Stack, the growing hole in Hole.io, the colour wheel in Color Switch as both menu and obstacle, Royal Match's in-scene stop cues, and Mini Metro's transit-map clock.

### Cited Findings
- Hypercasual games often move HUD-style information into the scene so the game explains itself without a tutorial — [AppLovin blog](https://blog.applovin.com/?p=25109) (via search summary)
- Stack's rising difficulty shows through shrinking platforms, and Hole.io's progress shows through the hole growing — [Pixune](https://pixune.com/blog/hypercasual-games-ui-ux-design-guide/)
- Color Switch's colour wheel is both a menu element and a gameplay obstacle — [Pixune](https://pixune.com/blog/hypercasual-games-ui-ux-design-guide/)
- Royal Match's production obstacles show the player when to stop matching, so no counting is needed — [Deconstructor of Fun](https://www.deconstructoroffun.com/blog/2021/3/21/royal-match-the-new-king-from-turkey)
- Mini Metro's UI copies the transit-map visual language, and its clock carries day/night colour — [Mechanics of Magic](https://mechanicsofmagic.com/2023/04/22/visual-design-of-games-mini-metro/)
- Threes' next-tile hint is a type/colour only, so the information format itself is a design lever — [Wired](https://hn.jakechampion.name/reader/http://www.wired.com/2014/05/threes-game-design)
- Block Blast's piece tray at the bottom is both the control surface and the "next" display — [Astana Hub](https://astanahub.com/en/blog/block-blast-the-addictive-puzzle-game)

### Inferences
- Possible mappings for Oina:
  - Knife throw: knife count as icons beside the log.
  - Stack and Helix: score drawn in the scene's sky or tower.
  - Water sort and Simon: no score at all.
  - Battleship: remaining ships as a fleet strip in the board frame.
  - Hangman: the gallows itself shows lives.
  - Minesweeper: mine counter and face built into the board bezel, as in the original.
  - 2048: a next-tile or score tile beside the board.
  - Block puzzle: piece tray at the bottom as the main control.
  - Solitaires: the stock and foundations act as the HUD.
- The Oina screen could be split into three bands that each game fills differently:
  - Top: a status strip that is optional and game-specific.
  - Middle: the board, the hero element.
  - Bottom: the game's own control surface (tray, keyboard, action buttons, or nothing for tap-anywhere games).

### Gaps
- No GDC talk or teardown was found that states this as an explicit design rule. The examples are descriptive.

## 3. Flows: tutorial, start, pause, fail, win, level select

### Takeaway
Retention-optimised games cut friction between attempts. Royal Match removed the level-start goal banner and the loading screens between retries. Hyper-casual games start on the first tap with an implicit cue (Crossy Road's arrow). The fail screen is the main point for a "continue / extra moves" offer. Exposition tutorials are discouraged in favour of contextual, in-play teaching.

### Cited Findings
- Royal Match removed the start-of-level goal banner and removed loading screens between retries to shorten attempts — [Deconstructor of Fun](https://www.deconstructoroffun.com/blog/2021/3/21/royal-match-the-new-king-from-turkey). A related analysis says the level-objective screen is skipped on retries — [search summary of Medium analysis](https://medium.com/@ekinmelissezer/game-analysis-for-royal-match-and-toon-blast-9c4bff8ef48b)
- Royal Match's fail flow offers "buy more moves" (900 coins as standard). Levels are tuned to end in an "almost win", so one or two moves would finish them. The game reshuffles the board when no moves remain instead of failing the player — [Deconstructor of Fun](https://www.deconstructoroffun.com/blog/2021/3/21/royal-match-the-new-king-from-turkey); the Royal Kingdom sequel keeps an identical buy-moves UI — [Deconstructor of Fun, Royal Kingdom](https://www.deconstructoroffun.com/blog/2024/07/01/royal-kingdom-will-it-outgrow-its-big-brothers-influence)
- Two Dots prompts the player to buy extra moves ($0.99) on running out — [Tom's Guide](https://www.tomsguide.com/us/two-dots,review-2201.html)
- Candy Crush shows a pre-level "level goals" screen with target and booster selection before play — [King help](https://community.king.com/en/candy-crush-saga/kb/articles/459-which-game-modes-will-i-find)
- Stack opens straight to the game screen and starts on a tap anywhere — [Supercent blog](https://medium.com/supercent-blog/designing-ui-of-hyper-casual-games-for-effective-user-experience-dd7c858bec82) (via search summary; page returned 403)
- Crossy Road's first road shows one forward arrow as an implicit "tap to go" tutorial, and Hole.io starts play as soon as the app opens — [Pixune](https://pixune.com/blog/hypercasual-games-ui-ux-design-guide/)
- Game-over screens should offer a quick restart. Pop-ups during gameplay should be avoided — [Pixune](https://pixune.com/blog/hypercasual-games-ui-ux-design-guide/)
- "Tutorial by exposition" (explaining outside gameplay) often confuses players. Contextual lessons are one of three tutorial types — [Udonis, mobile game tutorial](https://www.blog.udonis.co/mobile-marketing/mobile-games/mobile-game-tutorial)
- Puzzle Retreat's tutorial is a visual cue to drag a block over holes, shown directly on the play surface — [Game Accessibility Guidelines](https://gameaccessibilityguidelines.com/puzzle-retreat-interactive-tutorial/)
- Re-showing a rule the first time a puzzle actually needs it (e.g. at level 4) works better than front-loading all rules — [itch.io dev post](https://itch.io/post/10581027)
- An unclear first-time user experience can sink games with good mechanics — [PocketGamer.biz](https://www.pocketgamer.biz/first-impressions-count-creating-the-ultimate-first-time-user-experience)
- Two Dots awards stars by moves left at completion and shows them with a score on the result screen — [TechCrunch](https://techcrunch.com/2014/05/31/two-dots-the-sequel-to-betaworks-dots-is-a-beautiful-monster/)

### Inferences
- Oina should use different start models per genre:
  - Arcade/timing games (flappy, stack, knife, helix, whack-a-mole): tap-to-start, with the idle scene showing the mechanic and a pulsing hand or prompt.
  - Puzzle and level games: play starts immediately, with the goal shown inside the board frame rather than in a modal.
  - Card and board games: the deal animation is the start.
- Retry should be one tap and skip any intro. The result screen should lead with the single next action ("Next" or "Retry") at thumb height, with stars and score above it.
- Pause can collapse into a small top-corner icon or a swipe-down sheet. Few referenced sources describe a full pause screen, which suggests pause is low-priority chrome in casual games.

### Gaps
- No sourced description was found of the specific "ghost hand" overlays used in Royal Match or Candy Crush tutorials, or of the level-select (saga map vs grid) choices in Flow Free, Unblock Me or Water Sort.
- No source covered the pause-menu contents of any named game.

## 4. Thumb-zone ergonomics on tall phones

### Takeaway
About half of phone use is one-handed thumb use, so frequent controls belong in the lower half. The top area suits glanceable, read-only status. Hoober himself now treats the rigid green/yellow/red heat-map as too simplistic.

### Cited Findings
- Hoober observed 1,333 people: 49% one-handed grip, 36% cradled (phone in one hand, the other hand taps), 15% two thumbs. Two-thirds of one-handed grips were right-handed — [UXmatters, How do users really hold mobile devices](https://www.uxmatters.com/mt/archives/2013/02/how-do-users-really-hold-mobile-devices.php); [A List Apart, How we hold our gadgets](https://hn.jakechampion.name/reader/http://alistapart.com/article/how-we-hold-our-gadgets)
- Hoober says the study isn't scientific, and he later updated his guidelines. The rigid heat-map is contested — [UXmatters](https://www.uxmatters.com/mt/archives/2013/02/how-do-users-really-hold-mobile-devices.php); [Monterail](https://www.monterail.com/blog/thumb-friendly-navigation-word-oriented-design)
- Top-right CTAs are poor ergonomic placement on large phones — [Atticus Li glossary](https://atticusli.com/behavioral-science-glossary/thumb-zone-design/) (low-authority source)
- A 2026 trend piece says social/meta features are moving to the lower corners — [EJAW, March 2026](https://ejaw.net/how-mobile-game-ux-interface-design-drives-player-retention-in-2026) (vendor blog)
- Limit active on-screen controls to 5–6 — [Epic Fortnite mobile docs](https://dev.epicgames.com/documentation/fortnite/designing-for-mobile-in-fortnite)
- Microsoft Solitaire Collection puts Undo and Hint at the bottom — [Wikipedia mirror](https://bafybeiemxf5abjwjbikoz4mc3a3dla6ual3jsgpdr4cjr3oz3evfyavhwq.ipfs.4everland.io/wiki/Microsoft_Solitaire_Collection.html)
- Block Blast's tray of three pieces sits at the bottom, the drag-start zone — [Astana Hub](https://astanahub.com/en/blog/block-blast-the-addictive-puzzle-game)

### Inferences
- Oina's current layout puts game buttons (undo, hint, restart) top-right, the hardest zone for a right-handed one-hand grip. Moving them to a bottom action row (as in MS Solitaire and Block Blast) matches the references.
- Keep the top band for read-only status (score, goal, timer) and rarely used exits (pause/close). Put frequent or critical actions, and the "next / retry" buttons on result screens, in the bottom third.
- Tap-anywhere games (flappy, stack, knife, helix, timing) need no bottom controls. The whole screen is the button, so the bottom can stay empty or hold the scene.

### Gaps
- No peer-reviewed study specific to portrait game HUD placement on 6.1–6.9" iPhones was found. The Microsoft "frequency-ranked placement" claim seen in search couldn't be traced to a primary source and was excluded.
