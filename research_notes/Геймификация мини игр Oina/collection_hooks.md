# How mini-game collections and daily-puzzle products hook players on first open and keep them returning (research notes for Oina)

Research date: 2026-11-13. Reliability is marked in-line: primary/company, reputable press, vendor or secondhand. Pre-2022 items are marked [older].

## 1. NYT Games (Wordle, Connections, Spelling Bee, Crossplay, Games app): daily puzzles, streaks, stats, sharing, hub

### Takeaway
NYT Games builds habit through one shared puzzle per day per game, a hard daily cap, streaks and stats per game, and a spoiler-free share artifact, all inside one subscription hub. Leadership says outright that it aims for a "healthy daily habit", not maximum time spent. It adds roughly one carefully chosen game a year rather than many. Scale is very large (11.2B plays in 2025), but Wordle's own volume is declining.

### Cited Findings
- NYT games were played a combined 11.2 billion times in 2025. Wordle accounted for 4.2 billion of those plays. — [AP via News4Jax, Jan 2026](https://www.news4jax.com/business/2026/01/21/this-just-in-from-the-new-york-times-its-first-2-player-game-and-an-evolving-business-model/)
- Wordle's 4.2B plays in 2025 work out to about 11.5M plays per day, down from 5.3B the year before. 2023 was 4.8B. NYT says the figures "can vary significantly" depending on how many puzzles go viral. NYT is planning a Wordle TV show partly to "re-energize" lapsed players. — [A Media Operator, Aug 2026](https://www.amediaoperator.com/analysis/wordle-tv-show-new-york-times-games-jonathan-knight/)
- Head of Games Jonathan Knight: "We're respectful of your time… We're not trying to get you in the app all day… We don't want 24/7 engagement", and he wants "a very healthy daily habit." — [AP via News4Jax](https://www.news4jax.com/business/2026/01/21/this-just-in-from-the-new-york-times-its-first-2-player-game-and-an-evolving-business-model/)
- Knight says NYT has "generally added one new game a year." He wants to avoid a site with "30 or so games, some of them low-quality." The Digits numbers puzzle failed after two attempts, which made the team cautious about math games. — [AP via News4Jax](https://www.news4jax.com/business/2026/01/21/this-just-in-from-the-new-york-times-its-first-2-player-game-and-an-evolving-business-model/)
- Business model: NYT had 12.33M subscribers by end of Sept 2025, up 9% year on year. About half buy the $30/month all-products bundle. A 2023 YipitData report found subscribers spent more time in Games than in the news product. The Games app was rebranded in 2020. — [AP via News4Jax](https://www.news4jax.com/business/2026/01/21/this-just-in-from-the-new-york-times-its-first-2-player-game-and-an-evolving-business-model/)
- Crossplay (Jan 2026), NYT's first designed multiplayer game: Scrabble-like, play against invited friends or a computer, in-game chat. It keeps records and adds "Cross Bot", a post-game analysis that suggests higher-scoring moves (the personalized review is for subscribers). It is a separate free app on iOS and Android. — [AP via News4Jax](https://www.news4jax.com/business/2026/01/21/this-just-in-from-the-new-york-times-its-first-2-player-game-and-an-evolving-business-model/); [WTOP search snippet of same AP story](https://wtop.com/consumer-news/2026/01/this-just-in-from-the-new-york-times-its-first-2-player-game-and-an-evolving-business-model/)
- Critic David Clamage argues that a game is harder to build content around when players aren't all reacting to the same daily puzzle. This points to the shared daily puzzle as a social and content engine. — [WTOP/AP snippet](https://wtop.com/consumer-news/2026/01/this-just-in-from-the-new-york-times-its-first-2-player-game-and-an-evolving-business-model/)
- NYT added in-app stats for Connections, including streaks and win rate. Knight framed this as supporting long-term engagement. — [Digital Trends](https://digitaltrends.com/gaming/nyt-connections-new-stats-feature)
- Streak salience: NYT's year-end data said the 2025 Wordle "BONGO" (May 14) ended 36,337 streaks, the year's biggest streak-buster. NYT publishes streak data as content. — [NBC New York](https://www.nbcnewyork.com/entertainment/entertainment-news/hardest-wordle-connections-games-2025/6436464/)
- 2023 figures [older than window but still useful]: Games app had 10M downloads in 2023, and there were 2.3B successful Connections solves that year. — [Axios, Jan 2024](https://www.axios.com/2024/01/29/wordle-nyt-games-news-media-layoffs)
- Wordle's origin of viral growth [older, 2021–22]: on Dec 16, 2021 Wardle added a share button that produces a spoiler-free emoji grid, after seeing an early player in New Zealand type grids out by hand. NYT bought Wordle on Jan 31, 2022 for a "low seven-figure sum." Reported counts went from about 300k daily players in early Jan 2022 to more than 2M by the end of January. These figures come secondhand and vary by source. — [CUNY Pressbooks](https://pressbooks.cuny.edu/inspire/part/the-wordle-effect-how-five-letters-changed-the-internet/); [WEF](https://www.weforum.org/stories/all/wordle-game-new-york-times-business-plan/)

### Inferences
- The NYT pattern breaks down into five parts: (a) one puzzle per day, the same for everyone; (b) a hard stop, so there is no binge or burnout; (c) streaks and stats per game; (d) a share artifact that reveals no answer; (e) a hub where finishing one game surfaces the next (Wordle → Connections → Spelling Bee). For Oina, a "Daily" row of 3–5 games (for example a fixed-seed sudoku, mate-in-N chess, a water-sort level and a 2048 target), each with an emoji-grid style share, maps directly onto this.
- NYT deliberately keeps its catalog small and curated. Oina has about 35 games, so first-open should spotlight a few rather than show a wall of 35. The daily set can act as the curated surface.
- Crossplay shows that even a daily-puzzle company adds async friend games with records and a post-game review. This fits Oina's Durak, Battleship and room features.

### Gaps
- I found no published NYT D1/D30 retention, average streak length, or share-rate data.
- I found no primary source on how the Games app hub orders games or recommends the next one. That is based on my own product knowledge and is not cited.
- Wordle's 2025 DAU (as distinct from plays) is not public. One blog figure of 4.5M daily players conflicts with others and is unverified.

## 2. Mini-game collections and brain-training bundles: onboarding, discovery, daily challenge, cross-game progression

### Takeaway
Brain-training bundles (Elevate, Lumosity, Peak) wrap many mini-games in a short daily "workout" (about 5 min), with adaptive difficulty, streak calendars, performance graphs and badges. Platform hubs (Apple Games app, Telegram) rely on friend challenges and social discovery. Curated "seasons" (Playdate) use scheduled drops of new games so there is always something new. Hard public retention data for these bundles is scarce.

### Cited Findings
- Elevate's own support page describes adaptive difficulty and a workout calendar for tracking streaks. — [Elevate support](https://support.elevateapp.com/hc/en-us/articles/4402922583067-What-is-Elevate)
- Elevate onboarding pitches "5 minutes a day" of personalized exercises on a value-proposition screen (captured screen flow). — [Reteno flow gallery](https://gallery.reteno.com/flows/emails-elevate); a comparison blog cites 150+ achievements in Elevate — [Nibble, vendor/competitor blog](https://nibble-app.com/blog/elevate-vs-lumosity)
- Peak: 40+ mini-games across memory, focus, problem-solving and reaction. Gamification includes per-session scores, daily streaks, badges and performance graphs (competitor-written comparison, so treat with caution). — [Moadly](https://moadly.app/news/peak-vs-lumosity-a-head-to-head-on-user-interface-and-gamification)
- Lumosity's onboarding explains the science up front to build credibility before play. Lumos Labs uses Braze messaging to keep users exercising and maintaining streaks. — [Braze case study](https://www.braze.com/customers/lumos-labs-case-study); [Screensdesign](https://screensdesign.com/apps/lumosity-brain-training/?vs=287355)
- Apple Games app (iOS/iPadOS/macOS 26, ships pre-installed). Its Friends tab shows what friends play and lets players invite friends to challenges or multiplayer. "Challenges" are score-based competitions built on Game Center leaderboards and do not require being Game Center friends. Players are notified automatically when a friend beats their score. Game Center games can show up in social recommendations on the Home and Friends tabs and in a "Top Played" chart. — [Apple Developer: Games app](https://developer.apple.com/games-app/index.html); [MacRumors guide](https://www.macrumors.com/guide/ios-26-games-app/)
- Telegram mini-games: there is no single marketplace, and discovery depends on word of mouth or channels. The App Center is the discovery surface. A vendor playbook suggests 10K+ users and D1 above 20% to rank. Helika reported Telegram game retention of 5–20%, versus 20–30% for traditional gaming benchmarks. — [HackerNoon](https://hackernoon.com/the-challenge-of-sustaining-mini-game-momentum-on-telegram); [The Block, Feb 2025](https://www.theblock.co/news/web3/2025-02-07-telegram-games-had-trouble-earning-revenue-retaining-users-in-q4-report-339563); [tgads playbook (vendor)](https://tgads.net/wiki/mini-app-launch-playbook)
- Mini-games hit a "novelty curve" quickly after short sessions, which is why streaks, progress and reasons to return matter. — [HackerNoon](https://hackernoon.com/the-challenge-of-sustaining-mini-game-momentum-on-telegram)
- Playdate [older, 2021–22, plus Season 2 in 2025]: Season 1 delivered 24 games over 12 weeks, 2 per week (up from the planned 1). The schedule starts when the owner first connects online. Titles were kept secret until they appeared, the "box of surprises" approach. Season 2 dropped 12 games over 6 weeks. — [VGC](https://videogameschronicle.com/news/playdate-handheld-console-pre-order-details-and-season-one-games-revealed); [iMore](https://www.imore.com/unlike-apple-arcade-playdates-seasons-model-offers-surprise-games-schedule)

### Inferences
- For Oina, a first-open "starter workout" of 3 very short games (about 60–90 s each, Elevate-style) could replace a catalog browse. It would set a streak on Day 0 and show the variety on offer.
- A Playdate-style unlock drip fits a 35-game app well. Show maybe 8–10 games on Day 1 and unlock 2 new ones per day or per streak day, which gives a reason to come back on Days 2–14 and paces discovery. The trade-off is frustration for users who want a specific game (such as Durak) right away. Keep friend-invited and multiplayer games always unlocked.
- Supporting Game Center leaderboards and Challenges gets Oina free distribution and friend-beat-your-score notifications on iOS 26. That is near-zero cost for score games (2048, Stack, Helix, flappy, road hop, knife).
- Cross-game progression (an account level, XP, badges or a collection across all games) is the brain-training standard. Performance graphs work for skill games (sudoku times, chess puzzle rating).

### Gaps
- I found no reliable published retention figures for Elevate, Lumosity, Peak, Brain Test, Gamezop or Google Play Games mini-games.
- I found nothing reliable on how Gamezop or WeChat mini-game hubs build their daily challenge or discovery. Searches returned no Gamezop-specific material.
- I found no source on what share of Apple Games app users use Challenges.

## 3. Hyper/hybrid-casual hits (Block Blast, Royal Match, Candy Crush, Helix Jump, Stack): first 30 seconds, meta layers, social

### Takeaway
The biggest 2025–26 puzzle hit, Block Blast, won on a tiny, endlessly replayable core plus massive A/B testing aimed at retention and playtime. It is mainly ad-funded. Royal Match won by removing meta friction (light castle-task meta, no story) and stacking optional live events on top of the level line. Retention benchmarks: global median D1 is about 23%, and puzzle has the best D7 of any genre.

### Cited Findings
- Block Blast (Hungry Studio) reported 70M DAU and 300M MAU worldwide as of Jan 2026, up from a previously reported 40M DAU / 160M MAU. The studio describes a year-long experimentation system running 10,000+ A/B tests. — [PocketGamer.biz](https://www.pocketgamer.biz/block-blast-reaches-70m-daily-active-users-and-300m-monthly-active-users-worldwide); [PocketGamer.biz 40M](https://www.pocketgamer.biz/block-blast-surges-past-40m-daily-active-users); [NextBigGames recap](https://nextbiggames.com/2026/01/18/%F0%9F%A7%B1-block-blast-hits-70m-dau-300m-mau-built-on-10000-tests/)
- Third-party figures conflict sharply. AppMagic via Udonis estimates about 17.3M average daily players, with D1 26.1%, D7 4.1%, D30 1.1% and D90 0.4%. A different (vendor-affiliated) article cites "Sensor Tower" figures of D1 51%, D7 32% and D30 21%. Hungry Studio says only that its D1/D7/D30 are "above industry averages." — [Udonis](https://www.blog.udonis.co/statistics/block-blast); [Global Games Forum](https://www.globalgamesforum.com/ctv/how-block-blast-shattered-records-with-ai-a-b-testing-and-a-bold-bet-on-long-term-players). These conflict, so treat all of them as unverified.
- Hungry Studio's philosophy is "simple to learn, challenging to master." Its North Star metrics are user retention and playtime. — [Global Games Forum](https://www.globalgamesforum.com/ctv/how-block-blast-shattered-records-with-ai-a-b-testing-and-a-bold-bet-on-long-term-players)
- Block Blast is ad-monetized. Hungry Studio has an AdMob success story focused on retention and revenue. Estimates put ad revenue at roughly $0.6–1M per day in 2025 (third-party estimates). — [Google AdMob case](https://admob.google.co.in/home/resources/hungry-studio-boosts-user-retention-revenue-with-admob/); [Udonis](https://www.blog.udonis.co/statistics/block-blast)
- Royal Match: Dream Games "took away all possible friction". It removed the written narrative and decoration customization that rivals had (Naavik). Live events add optional goals on top of the main level progression, so players "can keep simply playing levels" (Funovus). — [Naavik deep dive](https://naavik.co/deep-dives/royal-match/); [Funovus](https://funovus.com/blogs/royal-match-dominates-match-3-what-can-all-designers-learn)
- A Deconstructor of Fun and Google talk (Istanbul Gaming Summit) advised treating pre-game and Day 0 retention (returning on the install day) as seriously as D1, because a Day-0 return correlates with retention. It also suggested making some themed live-event content free, and said fun is the biggest retention driver. — [This Week in LiveOps #3](https://thisweekinliveops.substack.com/p/this-week-in-liveops-royal-matchs)
- Royal Kingdom (Dream Games' second title) makes it easier to balance the campaign and matchmake players for live events. Deconstructor of Fun raises concerns that it cannibalizes Royal Match's most engaged players. — [DoF 2024](https://www.deconstructoroffun.com/blog/2024/07/01/royal-kingdom-will-it-outgrow-its-big-brothers-influence)
- Benchmarks: GameAnalytics Q1 2024 global medians were D1 22.91%, D7 4.20% and D28 0.85%. Puzzle had the highest D7 of all genres. 2024 top-quartile D1 was about 26.5–27.7%, and iOS beat Android (about 31–33% vs 25–27%). — [GameDevReports summary of GameAnalytics Q1'24](https://gamedevreports.substack.com/p/gameanalytics-benchmarks-in-mobile); [GameAnalytics 2025 benchmarks PDF](https://investgame.net/wp-content/uploads/2025/02/2025-GameAnalytics-Mobile-Gaming-Benchmarks.pdf)
- Top-2% hypercasual median retention was D1 45% (iOS) / 40% (Android) and D7 17% / 13% (date unclear, likely pre-2022) [older?]. — [GameDevReports: GameAnalytics hypercasual snapshot](https://gamedevreports.substack.com/p/gameanalytics-hypercasual-games-metrics)

### Inferences
- First 30 seconds: Block Blast, Helix Jump and Stack drop the player straight into play with no menu, account or tutorial text. An implied interactive hint (a hand animation) teaches the one verb (drag, hold, tap). The first loss comes fast and restarts instantly. For Oina, first open should launch directly into one short game (for example Block puzzle or Stack) before showing the hub. Oina's hand-built game screens should support "tap to start" with no modal.
- Day 0: per the DoF talk, design a reason to come back on the same day. Examples are a second daily puzzle unlocking after a few hours, or a "come back tonight" event, a cheap win for a multi-game app.
- Meta: Royal Match shows a light meta (one progress bar, task stars) beats a heavy one. For a collection, a single cross-game meta (account XP → unlock games, themes or board skins, plus a collection album of badges per game) is cheaper and more coherent than per-game decoration.
- Events: optional time-boxed goals laid on top of normal play (for example "this weekend: clear 50 lines in any block game" or "win 5 Durak hands") reuse existing games with no new content.
- Social: Game Center leaderboards and Challenges for score games, async friend rooms for turn games (Durak, Battleship, chess), and shareable result cards for daily puzzles cover all three social modes.

### Gaps
- I found no reliable primary teardown of Block Blast's or Helix Jump's first-session flow. The first-30-seconds notes above are inference from general knowledge, not cited.
- I could not fetch the Funovus and Naavik pages in full (connection errors). The Royal Match event specifics (King's Cup, Lightning Rush, team battles) and Candy Crush's onboarding and streak mechanics are not verified here.
- I found no published season-pass impact numbers for puzzle titles.
- I found no Sensor Tower or data.ai primary report on Block Blast retention, and the D1/D7 numbers I did find conflict sharply.

## 4. Notifications and widgets in daily return

### Takeaway
The most credible evidence comes from Duolingo: widget users retain much better (observational), and push copy framed around the user's own goal and streak lifted DAU about 5%. Gaming-specific push data is mostly vendor case studies. Apple's iOS 26 Games app adds system-delivered "friend beat your score" notifications for Game Center games. NYT's philosophy sets a useful ceiling: avoid nagging.

### Cited Findings
- Duolingo says learners using its home-screen widget had "far better retention", even after controlling for the fact that more committed learners add widgets. No effect size is given. The widget changes state to reflect whether the day's lesson is done. — [Duolingo blog](https://blog.duolingo.com/widget-feature)
- In a Duolingo A/B test, reminder copy framed around the user's own goal and streak, rather than generic "come back" copy, raised DAU by 5% (secondhand). — [Taplytics](https://taplytics.com/blog/how-duolingo-ran-an-experiment-on-their-streaks-feature)
- Duolingo found users who reached a 10-day streak were less likely to drop off (correlation). — [Substack analysis](https://marishalakhiani.substack.com/p/breaking-down-duolingos-growth-model)
- Duolingo's 2022 experiments included widgets whose mood changes when the user skips, special streak app icons, goal-commitment copy and "Perfect Streak Week". No effect sizes are given (secondhand). — [Lazyweb](https://lazyweb.com/research/duolingo-retention-experiments)
- Game push case study (vendor, OneSignal): Beach Bum Games saw push CTR rise from under 1% to 12% in a Gin Rummy campaign, quest-related CTR up 250%, paid-user reactivation up 140% after 10 days, and up to 4% engagement lift from translated pushes. — [OneSignal case via casestudies.com](https://www.casestudies.com/company/onesignal/case-study/beach-bum-games-uses-onesignal-to-drive-player-retention)
- Apple Games app: Game Center notifies players automatically when a friend beats their score. — [Apple Developer: Games app](https://developer.apple.com/games-app/index.html)
- NYT's stated stance: not "24/7 engagement" but "a very healthy daily habit." — [AP via News4Jax](https://www.news4jax.com/business/2026/01/21/this-just-in-from-the-new-york-times-its-first-2-player-game-and-an-evolving-business-model/)

### Inferences
- Oina plan:
  - One opt-in daily reminder at a user-chosen time, asked for after the first completed daily puzzle, not on first launch, with copy built on the streak or goal ("Your 6-day streak: today's sudoku is ready").
  - Event-driven pushes for friend actions: room invite, "your turn" in Durak or Battleship, friend beat your score.
  - A WidgetKit widget showing today's daily puzzle state, streak count and maybe a mini 2048 or sudoku preview.
  - Localize push copy, since Oina ships 8 languages and the OneSignal case notes translation lifts engagement.
- A streak-freeze or repair mechanic softens streak-busters like Wordle's BONGO day.

### Gaps
- I found no credible peer-reviewed or large-sample benchmark on push lift for casual puzzle games. Search results were vendor material or spam mirrors.
- I found no published data on the retention impact of widgets for NYT Games or any puzzle game.
- I found no data on iOS Live Activities for turn-based games.
