# Game feel, tactile-toy presentation and in-game HUD for Oina (SwiftUI, ~35 casual games)

Research note scope: game-feel theory, iOS haptics, soft/toy-like art direction, HUD placement on iPhone, win/lose and restart moments. Several primary sources (gamedeveloper.com, funovus.com, creativereview.co.uk) refused automated fetches during this session (connection reset / 403), so some findings rest on search-result summaries rather than full-page reads. This is flagged where it matters.

## 1. Game-feel principles: which feedback layers matter most, and how to keep them tasteful

### Takeaway
Game feel is real-time control plus a readable simulated space plus polish. The polish layer that matters most for short casual games is: an immediate response to every touch, eased and squashy motion, a matching sound and haptic, and a brief emphasis (a micro-pause or scale pop) on big moments. Shake, hit-stop and particles are for rare peaks, not every action. A recognised counter-argument (Folmer Kelly, 2014) warns that juice applied without regard to context reduces immersion.

### Cited Findings
- Steve Swink defines game feel as "real-time control of virtual objects in a simulated space, with interactions emphasized by polish". The three pillars are real-time response, simulated space and polish — [Wikipedia: Game feel](https://en.wikipedia.org/wiki/Game_feel); [Liz England review of Swink](https://lizengland.com/blog/review-game-feel-by-steve-swink/)
- Swink describes "the aesthetic sensation of control" as the player's pleasure in manipulating an object and sensing its response. In his framing, simulated space includes a sense of weight, gravity, speed and collision — [Wikipedia: Game feel](https://en.wikipedia.org/wiki/Game_feel)
- The definition is contested. Doug Wilson separates "Game Feel" (Swink's feeling of control) from "game feel" (any feeling a game communicates) — [Wikipedia: Game feel](https://en.wikipedia.org/wiki/Game_feel); [arXiv 2011.09201](https://arxiv.org/pdf/2011.09201)
- "Juice It or Lose It" by Martin Jonasson and Petri Purho is listed under GDC Europe 2012. In it they take a plain Breakout prototype and add "juicy" effects live. Some sources place the first showing at Nordic Game in May 2012, so the venue is reported inconsistently — [GDC Vault](https://gdcvault.com/play/1016487/Juice-It-or-Lose); [Juicy Break, itch.io](https://crcdng.itch.io/juicy-break)
- A university lecture deck on game feel groups juice techniques into tweening/easing (position, rotation, scale), colour, random delay and deformation (stretch). It links the open-source "juicy-breakout" project — [GxD 10 Game Feel, Uni Bayreuth](https://medienwissenschaft.uni-bayreuth.de/wp-content/uploads/GxD-10-Game-Feel.pdf)
- Jan Willem Nijman's "The Art of Screenshake" (INDIGO 2013) starts from a dull shooter and adds about 30 small tweaks. The items recorded in recreations and handouts include: basic animation and sound, lower enemy HP, bigger explosions, permanence (smoke and debris that stay), muzzle flash, faster bullets, knockback, camera lerp, screenshake, hit pause, recoil, slow motion and a meaningful game-over screen. Nijman's Nuclear Throne pistol example kicks the camera 6 px and adds 4 shake that decays quickly. I could not retrieve the full numbered list — [search summary incl. DK Liao recreation devlog](https://dkliao.itch.io/the-art-of-screenshake-recreation/devlog/451576/quick-breakdown-of-all-the-effects); [Game Developer write-up](https://gamedeveloper.com/design/vlambeer-co-founder-shares-advice-on-building-better-action-games) (fetch failed; summary only)
- Community commenters on the talk note that screenshake is easily overdone and that some of the tricks detract from the experience — [makegamessa thread](https://makegamessa.com/discussion/comment/16542) (search snippet only)
- Counterpoint: Folmer Kelly's "Don't Juice It or Lose It" (GDC Europe 2014, Independent Games Summit) argues that the focus on eye candy ignores context, so adding polish can actually lose immersion — [GDC Vault](https://gdcvault.com/play/1020861/Don-t-Juice-It-or); [Game Developer coverage](https://gamedeveloper.com/design/video-indies-resist-the-urge-to-juice-it-or-lose-it-)
- A Game Developer article argues that screen shake and squash-and-stretch only suit particular situations and should match the core gameplay — [Squeezing more juice out of your game design](https://gamedeveloper.com/design/squeezing-more-juice-out-of-your-game-design-) (search snippet; fetch failed)
- Hit-stop numbers from practitioner guides (secondary sources, aimed at action games): typically 2–5 frames, or about 30–50 ms light, 60–100 ms heavy and 100–150 ms critical. Dead Cells is cited at 2–3 frames on contact, longer on kills. Guides advise freezing only the involved actors rather than the UI and audio, and timing in seconds rather than frames (120 Hz displays halve frame-based waits) — [uhiyama-lab Unity primer](https://uhiyama-lab.com/en/notes/unity/unity-game-feel-hit-feedback/); [bugnet hitstop](https://bugnet.io/blog/how-to-fix-hitstop-or-freeze-frame-feeling-off); [Godot forum checklist](https://forum.godotengine.org/t/game-feel-checklist-for-godot-4-hit-stop-trauma-shake-coyote-time-and-more/145340)
- Squash and stretch practice: deform on landing or impact while conserving volume (stretch one axis, squash the other), then spring back with overshoot. A Godot example uses scale (1.3, 0.7) tweened back with elastic ease-out. For subtle UI, 5–10% deformation is suggested — [uhiyama-lab](https://uhiyama-lab.com/en/notes/godot/hit-feedback-hitstop/); [coddy squash & stretch](https://coddy.tech/learn/godot/game_feel/squash_and_stretch) (secondary/practitioner sources)

### Inferences
- Priority order for a calm "tactile toy" casual collection, from most to least important:
  1. Instant touch response: a press state within the same frame, plus a light or soft haptic.
  2. Eased, springy motion on every move. In SwiftUI, `.spring(response: 0.3…0.45, dampingFraction: 0.6…0.8)`.
  3. Squash and stretch of 5–12% on place, land or merge.
  4. A synced sound and haptic, matched in sharpness.
  5. Small particles and confetti, reserved for clears, merges and wins.
  6. A 60–120 ms micro-freeze on big combos or the final move.
  7. Screen shake, rarely. Use small amplitude and fast decay, and only for impacts that fit the toy fiction, such as a stack collapsing or a bomb in Battleship.
  This tiering is my synthesis of the sources above, not a quoted rule.
- "Permanence" (Nijman) maps well to toy style. Objects can leave soft dents, crumbs, rings or settled pieces rather than vanishing.
- To stay tasteful, scale intensity with significance (a small tap gets a small response, a win a big one), cap concurrent effects, honour Reduce Motion, and avoid shake in calm and puzzle games where it reads as error or stress (Kelly's context argument).

### Gaps
- I could not read the full "Juice It or Lose It" or "Art of Screenshake" talk contents or transcripts (video only; fetches failed). The exact technique lists above are partial.
- I found no tuning data specific to mobile puzzle or casual games (hit-stop, shake amplitude). The numbers come from action-game guides.

## 2. iOS haptics best practice for games

### Takeaway
Apple's HIG says to use system haptics only for their documented meanings, keep each haptic consistently tied to one cause, harmonise haptics with the animation and sound, prefer short transient haptics for discrete events, avoid overuse, and always make haptics optional. Use Core Haptics for custom patterns (transient and continuous events with intensity and sharpness, optionally synced with audio).

### Cited Findings
- "Use system-provided haptic patterns according to their documented meanings." If the meaning doesn't fit, use a generic pattern or a custom one — [HIG: Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
- "Use haptics consistently." Build a clear causal relationship. Example: a pattern used for mission failure must not also be used for level completion — [HIG: Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
- Complement other feedback: "match the intensity and sharpness of a haptic with the intensity and sharpness of the animation it accompanies". Sound can be synchronised with haptics — [HIG: Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
- "Avoid overusing haptics … the best haptic experience is one that people may not be conscious of, but miss when it's turned off" — [HIG: Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
- Prefer short haptics for discrete events. Long-running haptics can enhance gameplay flow but dilute meaning in apps — [HIG: Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
- "Make haptics optional": let people turn haptics off, and keep the game enjoyable without them — [HIG: Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
- Custom haptics: games often use them. Transient events (taps/impulses) and continuous events (sustained vibration) are each controlled by intensity and sharpness. Sharpness conveys "soft, rounded, or organic" versus "crisp, precise, or mechanical". Haptics can vary dynamically, for example a jump from a tree hits harder than a jump in place — [HIG: Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
- UIFeedbackGenerator families on iPhone:
  - Notification: success, warning, error (for task outcomes).
  - Impact: light, medium, heavy, rigid and soft (soft is for "soft or flexible UI objects", rigid for "hard or inflexible").
  - Selection: for values changing.
  — [HIG: Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
- iPad has no built-in haptics (game controllers can play them) — [HIG: Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
- Touch controls should have "visible and tactile press states", combining the visual press state with sound and haptics — [HIG: Game controls](https://developer.apple.com/design/human-interface-guidelines/game-controls)
- HIG "Designing for games" recommends adopting Core Haptics to compose custom patterns combined with audio — [HIG: Designing for games](https://developer.apple.com/design/human-interface-guidelines/designing-for-games)
- Relevant WWDC sessions: WWDC19 "Introducing Core Haptics" (520) and "Expanding the Sensory Experience with Core Haptics" (223), and WWDC21 "Practice audio haptic design" (10278) — [WWDC19 520](https://developer.apple.com/videos/play/wwdc2019/520); [WWDC19 223](https://developer.apple.com/videos/play/wwdc2019/223); [WWDC21 10278](https://developer.apple.com/videos/play/wwdc2021/10278)

### Inferences
- A shared Oina haptic vocabulary, to be used identically in all 35 games:
  - Selection for drag-over cells and pickers.
  - `.soft` impact for clay/plastic pieces landing.
  - `.rigid` for hard snaps such as tile slams in 2048 or a peg click.
  - `.light` for minor taps.
  - `.medium` or `.heavy` only for big merges and collapses.
  - `notification(.success)` reserved for a win.
  - `notification(.error)` or `(.warning)` for an invalid move or a loss. Never swap these.
- The "soft" sharpness and impact style fits the clay/plastic art direction. Keep sharp or rigid haptics for hard materials so material and haptic agree, as the HIG asks for intensity and sharpness to match the visual.
- Throttle repeated haptics (for example, at most one selection tick per cell, with a minimum interval) so they don't blur together. Expose a single global haptics toggle in settings.

### Gaps
- I did not retrieve the full WWDC transcripts, so there is no quoted guidance on audio-haptic sync latency or `CHHapticEngine` lifecycle best practices.

## 3. Tactile/toy-like 3D art direction (Monument Valley, Alto, Townscaper, soft 3D)

### Takeaway
Successful "calm premium" mobile art uses a restricted palette per scene, custom simplified lighting (directional light, colour applied directly, baked ambient occlusion, vignettes and faked glows) rather than realism, flat or low-poly forms, and deliberate removal of tools and detail. The same look can be faked in 2D/SwiftUI with 2–3 tone faces, gradients, inner highlights and soft contact shadows.

### Cited Findings
- Monument Valley (Ken Wong, GDC 2015 "The Art of Monument Valley"): influences include Escher, Middle Eastern architecture, Japanese flower arrangement and low-poly 3D art — [GDC Vault](https://gdcvault.com/play/1025003/The-Art-of-Monument-Valley); [Creative Bloq making-of](https://creativebloq.com/computer-arts/making-monument-valley-71412213)
- Monument Valley lighting: custom shaders with a custom directional lighting model instead of standard Unity surface shaders, so colour is applied directly. This is combined with lightmapped static ambient occlusion and "hefty overdraw for vignetting and faked volumetric glows". Each level's palette "evolved very organically". Wong: "We removed a lot of tools from the artist's toolbox." — [search summary of Creative Bloq / MCV](https://creativebloq.com/computer-arts/making-monument-valley-71412213); [MCV Unity focus](https://www.mcvuk.com/development/unity-focus-monument-valley) (search snippets; not fully fetched)
- In Monument Valley II, a narrative turning point introduces a new colour palette and style (David Fernandez Huerta, GDC 2018) — [Creative Review](https://www.creativereview.co.uk/monument-valley-us-two/) (403 on fetch; snippet only); [CGWorld GDC 2018 report](https://cgworld.jp/feature/201804-gdc2018pt3.html)
- Alto's Adventure: Snowman wanted a minimalist, "moving art" look and to move away from the arcade tone of most games. Harry Nesbitt's art is angular and flat with subtle parallax and took many iterations — [80.lv](https://80.lv/articles/altos-adventure-a-game-with-style); [Cult of Mac](https://www.cultofmac.com/news/altos-adventure); [Siliconera](https://siliconera.com/altos-adventure-one-pretty-snowboarding-game)
- Townscaper (Oskar Stålberg): flat-shaded styles and simple lighting help a game look appealing at low performance cost. That line may be the interviewer's paraphrase rather than Stålberg's words. The lighting/sun is user-adjustable and produces long light streams and shadows. The official framing is a "calming art style". The pastel palette description comes from weak sources — [XR AI Spotlight interview](https://xraispotlight.substack.com/p/how-to-make-procedural-generation); [PC Gamer](https://www.pcgamer.com/townscaper-game-of-the-year-personal-pick); [Raw Fury press release](https://gamespress.westeu-v2.propressroom.com/Oskar-Stalberg-Raw-Furys-Townscaper-Is-Now-Officially-Available-on-Nin)
- Royal Match is widely described as extremely polished in animations, UI and art. A Funovus analysis argues its UI animations communicate "simplicity, polish, and focus". Deconstructor of Fun suggests higher saturation of power-ups improves clarity — [Funovus](https://funovus.com/blogs/royal-match-dominates-match-3-what-can-all-designers-learn) (snippet; fetch failed); [Deconstructor of Fun: Makeover Match](https://www.deconstructoroffun.com/blog/2023/6/4/iteration-over-innovation)

### Inferences
- A recipe for the Oina "tactile toy" style in SwiftUI 2D/pseudo-3D:
  - **Light:** one fixed top-left key light across the whole app.
  - **Shading:** each object gets a base colour, a lighter top face or highlight (inner gradient, `.overlay` with white at 25–40% at the top) and a darker side or bottom lip of 2–6 pt offset in a darker shade of the same hue.
  - **Shadows:** two shadows, a soft wide ambient one (low opacity, large radius, y-offset) and a tight contact shadow under the object. This approximates Monument Valley's "colour applied directly + baked AO".
  - **Palette:** a limited set per game (3–5 hues plus one neutral board colour), desaturated and calm. Reserve saturated accents for interactive or important items, consistent with the Royal Match/DoF clarity point.
  - **Background:** a gentle vignette or radial gradient to frame the board as a diorama.
- "Removing tools" matters for a 35-game collection. Define a single material and lighting token set (corner radius, bevel depth, shadow pair, highlight) and apply it everywhere, so games feel like one toy box.
- Pressing a toy object should physically depress it: reduce the bevel lip offset, shrink the shadow and scale to about 0.96, then spring back. This links the art style to game feel.

### Gaps
- No primary-source analysis was found of Block Blast, Mini Metro/Mini Motorways, Lumino City or recent Apple Arcade "soft 3D/clay" titles. I found no authoritative write-up on the "claymorphism"/soft-3D mobile trend itself.
- The full Ken Wong GDC talk was not transcribed. Palette specifics such as values and counts are unavailable.

## 4. HUD placement: minimal, in-world HUD on iPhone

### Takeaway
Apple's guidance: design for full screen, keep controls out of the Dynamic Island and Home indicator, put frequent actions near the thumb and secondary controls (menus/pause) at the top, size primary targets at 44x44 pt or more (28x28 pt minimum for secondary), keep text at 11 pt or more, prefer direct manipulation of game objects over overlay buttons, and hide controls that aren't currently relevant. This supports replacing a big shared header with a small top-corner pause plus game-specific in-world score/goal elements.

### Cited Findings
- "Design for the full-screen experience." People enjoy distraction-free full-screen play — [HIG: Designing for games](https://developer.apple.com/design/human-interface-guidelines/designing-for-games)
- Integrate device features such as rounded corners and the camera housing into layout, relying on platform safe areas. In-game menus must adapt to 16:10, 19.5:9 and 4:3 without obscuring content, using relative constraints, not fixed layouts — [HIG: Designing for games](https://developer.apple.com/design/human-interface-guidelines/designing-for-games)
- Place virtual buttons so they don't overlap the Home indicator or Dynamic Island. Put frequently used buttons near the thumb and "secondary controls, like menus, at the top of the screen" — [HIG: Game controls](https://developer.apple.com/design/human-interface-guidelines/game-controls)
- Frequent controls should be at least 44x44 pt and less important controls (menus) at least 28x28 pt. iOS text defaults to 17 pt with an 11 pt minimum — [HIG: Game controls](https://developer.apple.com/design/human-interface-guidelines/game-controls); [HIG: Designing for games](https://developer.apple.com/design/human-interface-guidelines/designing-for-games)
- "Look for opportunities to reduce the amount of virtual controls that overlap your game content by associating actions with in-game gestures instead", such as tapping objects rather than a selection button. "Show and hide virtual controls to reflect gameplay" to reduce clutter — [HIG: Game controls](https://developer.apple.com/design/human-interface-guidelines/game-controls)
- Use symbols that communicate the action rather than abstract labels — [HIG: Game controls](https://developer.apple.com/design/human-interface-guidelines/game-controls)
- Text must contrast well with the background. Don't rely on colour alone. Let players customise motion intensity, sound balance and similar settings — [HIG: Designing for games](https://developer.apple.com/design/human-interface-guidelines/designing-for-games)
- Royal Kingdom/Royal Match UI is described as clean and easy to parse — [Deconstructor of Fun: Royal Kingdom](https://www.deconstructoroffun.com/blog/2023/05/09/royal-kingdom-will-it-usurp-the-throne) (snippet)

### Inferences
- A suggested per-game HUD pattern for Oina, synthesised from the HIG plus common genre convention (convention not sourced):
  - **Top-leading corner:** a small 44 pt "pause/back" toy button below the safe area.
  - **Top-trailing:** at most one secondary button (help or restart).
  - **Score and best:** a single compact pill placed near the board or, where the fiction allows, on it, for example engraved on the board frame or shown as a token stack. Not a full-width header.
  - **Goals/moves (match-3 style):** a small in-world plaque attached to the board.
  - **Primary actions (piece tray, fire button):** the bottom third, in the thumb zone, above the Home indicator.
- Let the board take the full width and as much height as possible, centred slightly below the vertical middle so it sits within thumb reach.
- Score changes should animate where they happen (a "+8" floats from the merge point to the score pill). This connects HUD and world, and is a juice technique.
- Hide non-relevant UI during play, for example the restart button only after first input, and the tutorial hint fading after the first move.

### Gaps
- I found no sourced breakdowns of exact HUD layouts in Royal Match, Candy Crush, Block Blast, Helix Jump, Stack, Threes! or the 2048 apps. Fetches of analyses (Funovus, Naavik, Game Developer) failed. Any specific claims about those games' HUD placement should be verified from screenshots.
- No Apple guidance or data was found on one-handed thumb-zone heat maps for portrait iPhone. The HIG heat map image is for landscape controls.

## 5. Win/lose and "one more try": fast restart and celebration design

### Takeaway
The sources support fast entry into play, a meaningful game-over moment (Nijman), and a consistent success haptic for wins. Concrete casual-game data on restart latency and celebration length was not found.

### Cited Findings
- Nijman's tweak list includes adding a game-over screen "for meaning" and slow motion at key moments — [GxD 10 Game Feel deck](https://medienwissenschaft.uni-bayreuth.de/wp-content/uploads/GxD-10-Game-Feel.pdf) (search summary)
- Apple: "Let people play as soon as installation completes". Provide great defaults. "Teach through play" via playable tutorials rather than prerequisite text — [HIG: Designing for games](https://developer.apple.com/design/human-interface-guidelines/designing-for-games)
- Notification success/warning/error haptics carry outcome meaning and must not be reused for opposite outcomes — [HIG: Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)
- Royal Match's level-end and UI animation polish is commonly cited as a reason for its quality perception — [Funovus](https://funovus.com/blogs/royal-match-dominates-match-3-what-can-all-designers-learn) (snippet)

### Inferences
- Loss flow:
  1. A short beat (about 300–600 ms) showing what went wrong, for example the board greys and the blocking cell wobbles.
  2. A warning or error haptic.
  3. A compact result card over the board, not a full-screen modal, with "Retry" as the large primary button in the thumb zone and the score and best shown.
  4. Retry returns to play in under about 1 second, with no interstitial.
- Win flow: a slow-motion or held final move, a success haptic synced with a sound and a confetti or toy burst, then a score count-up animation into the "best" pill. Keep the total under about 2–3 s and skippable on tap.
- A "near-miss" display (for example "3 points from your best") is a common motivational device, but this is unsourced here.

### Gaps
- No sourced data on optimal restart latency, celebration duration or near-miss framing in casual mobile games. GDC talks on retention and "one more try" (for example from Supercell, Voodoo or Dream Games) were not retrieved.
