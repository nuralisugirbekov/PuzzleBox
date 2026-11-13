# Gamification Mechanics and Retention in Casual Mobile Games: Evidence vs Backfire (for Oina)

Research date: 2026-11-13. These notes are for Oina, an iOS collection of about 35 short casual games with friends and online rooms. Evidence quality is marked as follows:
- **[A/B]**: controlled experiment
- **[academic]**: peer-reviewed
- **[vendor]**: industry or vendor data with a commercial interest
- **[corr]**: correlational only

Older material is labeled with its year.

## 1. Benchmarks: typical D1/D7/D30 retention for casual/puzzle mobile games (2023–2026)

### Takeaway
Median mobile games now hold only about 22–27% of players on D1, about 4–8% on D7 and under 1–3% on D30. Top-decile games reach about 40% D1 and 11–12% D7. Puzzle is one of the better-retaining genres: published genre tables put it at roughly 30–40% D1, 10–20% D7 and 3–7% D30. A realistic "good" target for Oina is about 35%+ D1, 10%+ D7 and 3–5% D30.

### Cited Findings
- GameAnalytics 2026 report (2025 data) covers 16,262 mobile games with at least 1,000 MAU, all genres together [vendor]:
  - D7 median is just under 4%. The top 25% reach 6–7%, the top 10% reach 11–12% and the top 1% exceed 25%.
  - D30 median is 0.69–0.79%. The top 25% reach about 1.6–1.8% and the top 1% reach 13–15%.
  - D1 is about 30%+ for the top 25%, about 40% for the top 10% and 64–68% for the top 1%. D1 declined in 2025 versus 2024.
  - Source: [GameDev Reports summary of GameAnalytics 2026 benchmarks](https://gamedevreports.substack.com/p/gameanalytics-mobile-and-pc-game)
- GameAnalytics engagement figures from the same report [vendor]:
  - Sessions per day: the top 25% average 5.3–5.7, the top 10% about 9.6 and the top 1% about 14.
  - Session length: about 5.2 min for the top 25% and about 8 min for the top 10%.
  - Daily playtime: 22–24 min for the top 25% and 40–42 min for the top 10%.
  - Source: [GameDev Reports](https://gamedevreports.substack.com/p/gameanalytics-mobile-and-pc-game)
- GameAnalytics 2025 report (2024 data) gives averages rather than medians: D1 26.48–27.69%, D7 about 8%, D30 under 3% — [2025 GameAnalytics Mobile Gaming Benchmarks PDF](https://investgame.net/wp-content/uploads/2025/02/2025-GameAnalytics-Mobile-Gaming-Benchmarks.pdf). Averages are pulled up by top games, so they are higher than the medians above.
- Puzzle genre figures:
  - Playio's genre table puts casual puzzle at about 30–40% D1, 10–20% D7 and 3–7% D30 — [Playio](https://blog.playio.co/retention-by-game-genre). It is not tied to a clearly dated dataset.
  - Segwise, citing Mistplay, puts puzzle at 31.85% D1, 12.18% D7 and 5.35% D30 — [Segwise](https://segwise.ai/blog/mobile-gaming-app-user-retention-strategies).
- Pushwoosh reports that 57% of Android users uninstall a game on the day they download it, and 75.4% within 30 days [vendor; older] — [PocketGamer.biz](https://www.pocketgamer.biz/android-games-struggle-to-retain-players-states-pushwoosh-report).

### Inferences
- Most churn happens in session 1 or on day 1. First-session experience and the D1 return trigger matter more than D30 meta-systems.
- Oina is a collection with friends and rooms, so a fair comparison is the puzzle/casual band (about 30–40% D1). The all-genre median sits around 22–27%.
- Sessions per day is a key KPI for a short-game collection. Top-quartile casual games get about 5 sessions per day, each about 5 minutes long.

### Gaps
- I could not see the numbers in Appodeal's [Mobile Casual Benchmarks Report 2025](https://files.gameindustrylibrary.com/documents/mobile-casual-benchmarks-report-2025.pdf), which has puzzle subgenre retention rankings; only chart titles were visible.
- I found no iOS-only puzzle benchmark. I also found no benchmark for "game collection / mini-game hub" apps specifically.
- Adjust, AppsFlyer and Liftoff 2025–26 gaming retention numbers were not retrieved.

## 2. Evidence per mechanic (streaks, daily challenges/rewards, XP, achievements, collections, leaderboards, friend challenges, push, variable rewards, onboarding, difficulty, near-miss)

### Takeaway
The strongest causal evidence is for these mechanics, mostly from Duolingo A/B tests:
- **Streaks.** Separating the streak from an intense daily goal raised D14 retention, and streak "insurance" mechanics (Weekend Amulet, Streak Wager) also tested positive.
- **Weekly competitive leaderboards.** Learning time rose 17% and D1/D7 improved significantly.
- **Social and friend features.** Positive but vendor-sourced, with effects up to 31%.

Daily rewards show small gains (about 1–8%) or none. Tutorials help only in complex games. Near-misses raise the urge to keep playing but borrow from gambling psychology. For achievements, collections, XP and variable rewards I found no game-specific causal retention numbers.

### Cited Findings

**Streaks (incl. freeze/repair)**
- Duolingo A/B test (2019–2020) separating the streak from the daily goal [A/B]: D14 retention +3.3% (relative), daily active learners +1%, and daily learners on a streak +10.5% after 20 days (+19% for new learners). Fewer learners completed their daily goal — [Duolingo blog, Nov 2020](https://blog.duolingo.com/improving-the-streak)
- Duolingo learners with a 7-day streak were 2.4x more likely to return the next day than learners without a streak [corr]. A year later, just over half of daily learners had a 7+ day streak, up from about a third — [Duolingo blog](https://blog.duolingo.com/improving-the-streak)
- Duolingo streak-insurance tests (2017) [A/B] — [Duolingo blog, May 2017](https://blog.duolingo.com/how-streaks-keep-duolingo-learners-committed-to-their-language-goals):
  - Streak Wager: D1, D7 and D14 retention rose significantly, with D7 +14%.
  - Weekend Amulet (protects the streak over weekends): learners were 4% more likely to return a week later and 5% less likely to lose their streak.
- Duolingo's former CPO Jorge Mazal (2023) says later streak improvements helped retention: calendar view, animations, streak freeze changes and streak rewards. He gives no numbers for streak freezes. He also notes the 10-day-streak/drop-off link may be selection bias — [Lenny's Newsletter](https://www.lennysnewsletter.com/p/how-duolingo-reignited-user-growth)
- Duolingo's Q2 2026 Streak Revival campaign: 15.4M learners revived their streaks, including nearly 8M who had no active streak. This was a campaign, not a controlled test — [Pulse2](https://pulse2.com/duolingo-daily-active-users-reach-58-7-million-as-retention-hits-record-84-and-social-accounts-top-1-billion-organic-impressions/)

**Leaderboards**
- Duolingo weekly leagues (about 2019) [A/B, as reported by its CPO] — [Lenny's Newsletter, 2023](https://www.lennysnewsletter.com/p/how-duolingo-reignited-user-growth):
  - Overall learning time +17%.
  - Highly engaged learners (1+ hour/day, 5 days/week) tripled.
  - D1 and D7 improved with statistical significance, but no figures are given.
- Education meta-analysis (2022): badges alone SMD = 0.33, leaderboards alone SMD = 0.27, gamification overall SMD = 0.39 [academic, education domain]. Cited via search summary of [Sailer & Homner related literature](https://opus.bibliothek.uni-augsburg.de/opus4/frontdoor/index/index/docId/109056); this is a secondary pointer and should be verified.
- Sailer & Homner meta-analysis (Educational Psychology Review, 2019/2020) [academic, education]:
  - Gamification effects: cognitive g = 0.49, motivational g = 0.36, behavioral g = 0.25. The motivational effects were less stable in rigorous studies.
  - Competitive-collaborative designs and a narrative frame were associated with larger effects.
  - Source: [Uni Augsburg OPUS](https://opus.bibliothek.uni-augsburg.de/opus4/frontdoor/index/index/docId/109056)

**Friends/social features and friend challenges**
- Discord Social Layer causal study (2025–26, more than 15 PC games): retention +31%, session length up to +47% and launch days up to +57% [vendor] — [PocketGamer.biz](https://www.pocketgamer.biz/discord-brings-social-layer-to-mobile-after-seeing-31-retention-increase-on-pc/)
- GetSocial: mobile players acquired through social referral had up to 67% higher retention and 63% more lifetime sessions [vendor, corr] — [PocketGamer.biz](https://www.pocketgamer.biz/mobile-gamers-referred-through-social-recommendation-have-up-to-67-higher-retention)
- Mistplay 2024: 15% of paying players spend more if they are actively engaged in a community [vendor] — [PocketGamer.biz](https://www.pocketgamer.biz/15-of-monetised-players-spend-more-if-actively-engaged-in-a-community)
- Meta's guidance says players whose friends play the same game return more often and play longer. It cites no dataset — [Meta for Developers](https://developers.facebook.com/documentation/games/retain/building-social-games)

**Daily rewards / login calendars / daily challenges**
- MobilityWare (solitaire) ran a 31-day multivariate test of opt-in reward cadences (daily, every 3 days, every 7 days) against a control. Result: about +4% DAU and +1–3% retention [vendor case study] — [Flurry case study](https://www.casestudies.com/company/flurry/case-study/how-mobilityware-used-flurry-to-boost-active-solitaire-users)
- Wonder Group reported +8% D1 after Daily Rewards campaigns. This was an offerwall/UA context, not an in-game login test [vendor] — [Unity](https://unity.com/resources/wonder-group)
- TapNation saw better early retention when daily rewards and challenges were triggered on later game starts rather than the first one. No figure is given [vendor] — [TapNation](https://wnk.tap-nation.io/?p=706)
- Counter-evidence: a developer reported an A/B test in which daily rewards did not raise playtime [anecdotal] — [Roblox DevForum](https://devforum.roblox.com/t/do-daily-rewards-actually-keep-players-retention/3556728)

**Push notifications**
- Duolingo treats push as a channel to protect. Raising notification volume required strong justification and CEO approval. Mazal cites Groupon, where aggressive email testing "basically destroyed their channel" — [Lenny's Newsletter](https://www.lennysnewsletter.com/p/how-duolingo-reignited-user-growth)
- Duolingo stops push reminders if a user has not returned after a week of them (Mazal, per secondary summary) — [Blitzllama summary](https://www.blitzllama.com/blog/duolingo-product-management-lessons)
- Google Play analysis: games that send more notifications per day have higher opt-out rates [corr] — [Google Play Dev, Medium](https://medium.com/googleplaydev/optimizing-notifications-in-games-5efd6ba89701)
- Pushwoosh: iOS game apps have a push opt-in rate of only 29.98%, the lowest of the industries it tracks (Android 83.2%). Players who opt out also play less [vendor] — [PocketGamer.biz](https://www.pocketgamer.biz/android-games-struggle-to-retain-players-states-pushwoosh-report)
- Braze survey: about 25% of users opted out because of too many notifications. The survey is small and not statistically significant — [Braze](https://www.braze.com/blog/opt-out-of-push-notifications-why-users-do-it/)

**Onboarding / tutorial length**
- Andersen et al., CHI 2012 (older): 8 tutorial designs tested across 3 games with more than 45,000 players [academic, A/B]:
  - In the most complex game (Foldit), tutorials raised play time by up to 29%.
  - In the simpler games (Refraction, Hello Worlds), the effect was negligible.
  - The authors say tutorials may not be justified when mechanics can be discovered by experimenting.
  - Source: [UW GRAIL project page](https://grail.cs.washington.edu/projects/game-abtesting/chi2012/)

**Near-miss**
- Larche, Musielak & Dixon (2017, Journal of Gambling Studies 33(2):599–615) [academic]:
  - Sixty Candy Crush players were tested; a near-miss was defined as missing a level by 1–3 moves.
  - Near-misses were more arousing than losses (higher heart rate) and triggered the strongest urge to keep playing of any outcome.
  - The authors frame this with slot-machine near-miss research.
  - Source: [PMC5445157](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5445157/)

**Need satisfaction / flow (SDT)**
- Ryan, Rigby & Przybylski (2006, Motivation and Emotion 30(4):347–363; older, but foundational) [academic]: perceived autonomy and competence predict enjoyment and well-being change. Autonomy, competence and relatedness each independently predict enjoyment and future play — [Springer DOI](https://link.springer.com/content/pdf/10.1007%2Fs11031-006-9051-8.pdf)

### Inferences
- **Streaks** fit Oina well because a daily game plus short sessions suits them. The tested lesson is to keep the daily requirement light (any one game counts) and to provide insurance such as a freeze, weekend protection or an earn-back wager. Duolingo's tests show protections increase retention rather than reducing urgency.
- **Leaderboards** work best when weekly, cohort-sized (Duolingo uses about 30-person leagues) and resetting. That gives every player a winnable tier, unlike a global all-time board. Friends leaderboards fit Oina's rooms; this is supported by the social-feature data and by SDT relatedness.
- **Daily rewards** are cheap but weak, at about 1–4% retention in the one real multivariate test. Treat them as polish, not a pillar. Do not show them in the very first session (TapNation).
- **Tutorials** for simple casual games should be minimal or contextual (Andersen 2012). Card and board games with real rules (e.g. Kazakh games) are more like the "complex" case and may benefit.
- **Near-miss** is a measurable lever for "one more try", but it rests on gambling-like arousal. Use honest "so close" feedback and avoid tuning outcomes to near-miss artificially.

### Gaps
- No quantitative public data on streak freeze or streak repair specifically. Duolingo mentions improvements without numbers, and "Behind the Product: Duolingo streaks" (Lenny's, Jackson Shuttleworth) was not fetched.
- No causal retention data for achievements/badges, XP/levels or collections in casual mobile games. The available meta-analyses are from education.
- No study found comparing global and friend leaderboards in mobile games.
- No game-specific causal data on variable-ratio rewards or on difficulty curves (flow / dynamic difficulty adjustment) and D7/D30.
- Octalysis (Yu-kai Chou) and Hooked (Nir Eyal) are frameworks with no published effect sizes. Searches did not surface empirical validations of either.
- No data on asynchronous friend challenges as a separate mechanic.

## 3. Academic and industry studies with numbers (Duolingo, SDT, Octalysis, Hooked)

### Takeaway
Duolingo is the richest public source of A/B numbers on streaks, leagues and notifications:
- Streak changes: D14 +3.3%, D7 +14%, return rate +4%.
- Leagues: learning time +17%.
- Its "current user retention rate" (CURR) metric drove a 4.5x DAU rise.

Academic work (SDT, gamification meta-analyses) shows small-to-moderate motivational effects (g ≈ 0.25–0.5) and stresses competence, autonomy and relatedness over points.

### Cited Findings
- Duolingo's growth model (Mazal, 2023) — [Lenny's Newsletter](https://www.lennysnewsletter.com/p/how-duolingo-reignited-user-growth):
  - CURR, the daily retention of already-active users, rose 21% over four years.
  - Daily churn among the best users fell by over 40%.
  - In their model, CURR had about 5x the DAU impact of the next-best lever.
  - DAU grew 4.5x in four years.
  - Learners with a 7+ day streak increased almost 3x, to more than half of DAU.
- Duolingo streak and league A/B tests: see section 2 — [Duolingo blog 2020](https://blog.duolingo.com/improving-the-streak), [Duolingo blog 2017](https://blog.duolingo.com/how-streaks-keep-duolingo-learners-committed-to-their-language-goals)
- SDT: autonomy, competence and relatedness predict enjoyment and future play — [Ryan, Rigby & Przybylski 2006](https://link.springer.com/content/pdf/10.1007%2Fs11031-006-9051-8.pdf)
- Gamification meta-analysis: motivational g = 0.36 and behavioral g = 0.25; social (competitive-collaborative) and narrative designs had larger effects — [Sailer & Homner](https://opus.bibliothek.uni-augsburg.de/opus4/frontdoor/index/index/docId/109056)
- AIIDE study of 21 free-to-play mobile games: ad exposure had a weak, non-significant effect on retention, and the game itself mostly determined retention [academic] — [AAAI AIIDE](https://ojs.aaai.org/index.php/AIIDE/article/download/12906/12754/16423)

### Inferences
- For Oina, the metric to watch is CURR-style retention of current daily players, not just new-user D1. Mechanics that protect existing habits (streak insurance, weekly leagues, friend rooms) offer the most leverage.
- Points and badges alone have small effects. Features that build competence (fair difficulty, visible mastery) and relatedness (friends, rooms) are better supported.

### Gaps
- No peer-reviewed numbers for Octalysis or the Hooked model.
- Duolingo is an education app, not a casual game. Effect sizes may not transfer one-to-one.
- GDC talks and Deconstructor of Fun teardowns with numbers (e.g. King, Playrix, Royal Match) were not retrieved.

## 4. What backfires, and regulation / App Store guidance on manipulative design

### Takeaway
The clearest evidence of harm:
- **Interstitial ads:** churn is much higher than with rewarded video, and some iOS games see 20%+ interstitial churn.
- **Notification overuse:** opt-outs rise with daily volume, and iOS game opt-in is already only about 30%.
- **Long tutorials in simple games:** no benefit.

Regulators are moving against virtual-currency obfuscation, loot boxes and addictive design for minors (EU DFA, expected Q4 2026; FTC v. Epic, $245M for dark patterns). Apple requires disclosed loot-box odds, non-coerced push opt-in and easily dismissible ads. I found no published data on energy systems or currency count.

### Cited Findings
- **Ads**
  - Unity AdQuality data: interstitials cause significantly higher churn than rewarded video. Churn varies up to 15x between ad networks, and on iOS interstitial churn exceeds 20% for some games [vendor] — [PocketGamer.biz](https://www.pocketgamer.biz/what-our-data-reveals-about-ad-quality-and-player-churn-in-mobile-games/)
  - Deloitte/AdMob diary study (50 gamers): disruptive full-screen ads were linked to shorter sessions, more quitting and churn [vendor-commissioned] — [Deloitte](https://www.deloitte.com/us/en/Industries/tmt/articles/improve-mobile-game-advertising.html)
  - Counterpoint: one casual game earned more revenue by showing interstitials more often, because most players churn early anyway — [Airflux](https://airflux.ai/blog/interstitial-ads-monetization). An AIIDE paper also found weak ad effects on retention — [AIIDE](https://ojs.aaai.org/index.php/AIIDE/article/download/12906/12754/16423)
- **Notification spam:** opt-outs rise with notifications per day — [Google Play Dev](https://medium.com/googleplaydev/optimizing-notifications-in-games-5efd6ba89701). Duolingo stops push after a week without a return and gates volume increases — [Lenny's](https://www.lennysnewsletter.com/p/how-duolingo-reignited-user-growth)
- **Loss aversion and streak pressure:** in Duolingo's 2020 test, removing the streak's dependence on an intense goal increased streaks and retention. This suggests that a harsh loss condition depresses retention — [Duolingo](https://blog.duolingo.com/improving-the-streak)
- **Near-miss** is documented with gambling-research methods as raising arousal and the urge to continue — [Larche et al. 2017](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5445157/)
- **FTC**
  - The 2022 staff report "Bringing Dark Patterns to Light" defines dark patterns as design that tricks or manipulates users. Examples include hidden costs, hard cancellation and sneaking items into carts. The FTC says it will enforce under the FTC Act, ROSCA and COPPA — [FTC report PDF](https://www.ftc.gov/system/files/ftc_gov/pdf/P214800%20Dark%20Patterns%20Report%209.14.2022%20-%20FINAL.pdf)
  - FTC v. Epic (2022–23): $245M in refunds for dark patterns pushing unwanted purchases, plus $275M COPPA penalty, $520M total — [Kelley Drye](https://www.kelleydrye.com/viewpoints/blogs/ad-law-access/two-epic-cases-from-the-ftc-spotlight-on-coppa-unfairness-teens-dark-patterns-in-app-purchases-cancellations-and-more.md)
- **EU**
  - The Commission's Digital Fairness fitness check found no EU rules that specifically cover addictive design, virtual items or in-app currencies. 47% of consumers were unsure what virtual items really cost — [Lewis Silkin](https://www.lewissilkin.com/en/insights/the-ecs-digitallegislation-for-video-games-companies-be-on-the-horizon), [Freshfields](https://technologyquotient.freshfields.com/post/102jqk8/digital-fairness-fitness-check-part-2-addictive-design-and-gaming)
  - The European Parliament's Nov 2025 non-binding resolution on protecting minors online passed 483–92–86. It calls for the Digital Fairness Act (DFA) to address loot boxes and in-app currencies, ban the most harmful addictive practices, and switch other addictive features off by default for minors — [DFA newsletter](https://newsletter.digitalfairnessact.com/p/european-parliament-adopts-protection-of-minors-online-report)
  - DFA proposal expected Q4 2026. A leaked draft (unconfirmed) would require showing real-money value for virtual-currency purchases and restrict paid loot boxes and pay-to-win for minors. It would also disable in-game currencies for under-18s without parental approval — [Inven Global](https://www.invenglobal.com/articles/28413/leaked-eu-digital-fairness-act-draft-would-ban-paid-loot-boxes-and-pay-to-win-for-minors), [PocketGamer.biz](https://www.pocketgamer.biz/leaked-eu-proposal-targets-loot-boxes-and-addictive-game-design)
- **Apple App Store Review Guidelines (current)** — [Apple](https://developer.apple.com/app-store/review/guidelines/):
  - §4.5.4: push must not be required for the app to work. Promotional push requires explicit in-app opt-in and an opt-out.
  - §5.1.2(i): apps may not require enabling push to get functionality or rewards.
  - §3.1.1: loot boxes must disclose odds before purchase.
  - §2.5.18: interstitial ads must be clearly labeled and not trick users into tapping. Close/skip buttons must be easy to see and large enough to dismiss easily.
  - §3.2.2(x): apps may not force ratings or reviews, but may reward in-app actions such as completing a level or watching an ad.
  - §1.3 / §5.1.4: Kids Category apps get no third-party ads or analytics, and purchases sit behind a parental gate.

### Inferences
- For Oina, ads should be rewarded-only (opt-in). Avoid interstitials between short games, which is exactly where a game hub would be tempted to put them.
- Push: ask for permission only after a meaningful moment, such as a friend invite or after a streak starts, never at launch. Keep push mostly to user-triggered events (a friend's challenge, your room is ready, streak at risk once per day). Stop sending to users who have been inactive for about a week.
- Avoid energy/lives gates for a short-game collection. They conflict with SDT autonomy and the sessions-per-day KPI, although I found no direct data.
- Keep at most one soft currency and show real prices. Upcoming EU rules target currency obfuscation, especially for minors. Kazakhstan's audience may include minors, which raises the bar.
- Streak loss messaging should not shame users. Offer earn-back or repair rather than permanent loss.

### Gaps
- No published data quantifying churn caused by energy systems — only a vendor page posing the question: [Bruin](https://getbruin.com/use-cases/mobile-gaming/energy-system-frustration-signals/).
- No data on the retention cost of multiple currencies.
- No direct data linking notification frequency to uninstalls in games; only opt-out correlation and small surveys.
- I could not confirm whether the EU DFA proposal was published as of 2026-11-13.
- Not retrieved: UK CMA or Norwegian Consumer Council ("Insert Coin", 2022) reports on game dark patterns, and Apple's Human Interface Guidelines on notifications.
