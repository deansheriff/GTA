# Naija Street Life — Reference Game Research Notes

**Subject:** the competitor at lagoslife.app ("the reference game").
**Session 1:** 2026-10-14, ~11:15–11:50 WAT. Desktop, in-app browser.
**Session 2:** pending, for retention and offline progress.

**Labels used below:**
- **[V]** Verified: observed directly in play, in network calls or in public JSON.
- **[I]** Inferred: reasoned from evidence, not confirmed.
- **[NO]** Not observed.

**Evidence:** screenshots are saved in `research-private/screens/`. That folder is
git-ignored because the images contain the competitor's art and other players'
usernames. The notes below summarise; they do not reproduce the game's text, code or art.

## 0. Method and limits
- **Account:** I can't create accounts or type passwords, so the owner logged in
  themselves. The account (`kinqdean`) **already had progress**: created 6 Oct 2026,
  Civil Service rank 2, Cooking 10, Coding 9, ₦1.69m. As a result:
  - [NO] I did not see true new-player onboarding (character creation,
    walkthrough, first 5 minutes). The settings menu has "Replay the walkthrough",
    which can be checked in session 2.
- **Play time:** ~35 minutes of active play and inspection in session 1.
- **Platform:** desktop only. Mobile web is not yet tested (it is a PWA).
- **What I didn't do:**
  - posted in public chat or messaged players
  - spent real money
  - completed the account's Tables or Bus Co. setup
- **Code:** I searched the client bundle only for keywords (e.g. NEPA, news, LLM)
  to classify systems. No code was copied.

## 1. What it is (confirmed by play)
- A free, browser-based, **massively-shared Sims-like life game** on a stylised
  Lagos. Abuja and Port Harcourt also exist as separate city maps. [V]
- Every player shares one world: ~54–56k online during the session, and a
  "41.0m visits" counter. [V]
- **Core loop** [V]:
  1. Pick a place from a map of ~35 pins.
  2. Pick a transport mode. Travel is an instant cut with a fare deducted.
  3. In the venue, tap activity cards. Each runs a real-time timer of 7–8s and
     costs game ₦.
  4. Needs refill and moodlets update.
- **Example:** Amala & Ewedu cost ₦200 and took ~8s; Hunger went from 0% to 70%. [V]
- **Session loop** [V]:
  - Daily: 3 missions (photo / visit 3 places / 4 conversations, one free swap),
    a 7-day login streak, and a daily "gem hunt" riddle that sends you to a venue.
  - Work: 1-hour job shifts.
  - Story quests: a few "Lagos Stories" per day.
  - Lagos Rep XP levels ("JJC" at level 2).
- **Session-to-session** [V]:
  - Lifetime "Dream" (aspiration), "Wishes" that earn ✨, and ✨ spent on perks
    (e.g. slower hunger decay, shorter jail).
  - Career ranks; skill rust after 7 days unused.
  - Property: homes, sea plots, cars.
  - Elections every week.

## 2. Systems
### Needs, mood and traits [V]
- **Six needs:** Hunger, Energy, Fun, Social, Hygiene, Bladder. These are direct
  Sims analogues.
- **Moodlets:** short Pidgin-flavoured lines with ± values, e.g. Starving −30,
  Smelly −15, Soft Life +10. Overall mood runs from Miserable to Fine and beyond.
- **Traits:** e.g. "Tech Bro or Sis", "Hustler".
- **Background:** e.g. "Nepo Baby: Daddy pays the rent", with a free car.
- **Sickness:** shows a "Sick · treat it" prompt.
- **Free will:** an autonomy toggle exists in settings.

### Careers and skills [V]
- **Careers:** ~15+ NPC careers per city. Each has 5 ranks, pay per 1-hour shift,
  and work days per week.
  - Lagos examples: Tech, Banking, Music (Shrine), Trading (Balogun), Nursing,
    Hairstyling, Chef (Amala Shitta), DJ (Quilox), Fitness, Content Creator,
    Teaching, Civil Service.
  - Abuja has its own list: Keke riding, Wuse Market, Mai Shayi, Lounge waiting.
- **Promotion** needs every box ticked: shifts at rank, a skill level and a Lagos Rep level.
- **Switching careers:** you keep rank if the new career uses the same skill.
- **Nine skills:** Cooking, Charisma, Fitness, Coding, Music, Hustle, Dance, Comedy, Photography.
- **Courses:** "UNILAG Short Courses" (lessons, then a quiz, then a certificate)
  give a career boost.

### Economy and money [V]
- Wallet in game ₦. **Real-money top-up via Flutterwave** (card, bank transfer, USSD):
  - ₦1,000 → +₦50k game money
  - up to ₦20,000 → +₦1.6m game money
- A "transaction PIN" option, an EFCC system that flags sudden wealth, and the
  rule "a raid never takes what you topped up".
- **Hyperinflation and a black market:**
  - The public feed is full of players selling game money for real naira at rates
    like ₦400 for 10 billion. That is thousands of times cheaper than the official
    top-up.
  - Players hold billions. Whot tables run ₦10m stakes; Big Man content is gated at ₦1bn.
  - [I] The official top-up is being massively undercut, and the economy's sinks
    can't keep up.
- **Bus Co.:** a tycoon sub-game. Buy HiAce or coach buses, set fares on
  Lagos–Abuja–PH routes, pay crews weekly.
- **Other phone apps:** Invest, Bank, Assurance, Health, Houses, Cars, Boutique,
  Shops (player shops), Staff, Family, Forbes (rich list).
- **LagosBet** [V]:
  - Sports betting on today's real club fixtures (real club names), results at 9 PM.
  - Also High-Low and Roulette.
  - Labelled 18+ and "game money can't be withdrawn".
  - [I] This is still gambling with currency that can be bought for real money, a
    regulatory grey zone.

### Time and events [V]
- An in-game clock and calendar run alongside real time.
- Day/night with an auto night mode.
- **NEPA outages** (confirmed by bundle keyword search and toasts):
  - Light goes off at home. A generator, solar or inverter upgrade keeps it on.
  - Night without a lamp gives a "Dark, hot and mosquitoes" moodlet.
  - Return of power shows an "UP NEPA!" toast.
- There is a governor policy "Steady light" (shorter, rarer cuts).
- **Scripted city-wide "events":** Lagos Flooding, Fuel Scarcity, CBN Rate Hike,
  Owambe Season, Apapa Gridlock, Storm Warning, Market Rally, Fintech Boom.
  These are **fictional/scripted, not real news**.
- **Venue flavour lines** rotate, e.g. "The queue is long but it's moving". [V]

### Travel and world [V]
- **The map is a small isometric diorama** with emoji pins and live billboards.
- **Travel** is a menu, not gameplay. Modes and fares:

  | Mode | Fare |
  |---|---|
  | Trek | free |
  | Keke | ₦150–200 |
  | Danfo | ₦150–200 |
  | Okada | ₦200–300 |
  | Cab | ₦400–550 |
  | Own car | ₦50 |

  You pick one, and after a short fade you're there. No danfo ride, no traffic,
  no go-slow gameplay.
- "Walk Yaba" appears to be a walkable district (not tested).
- **Venue gating:**
  - Ikoyi Golf Club and "Big Man Night" at Quilox need a ₦1bn net worth.
  - The "Lost Bag" story quest sends you to the Golf Club. A player worth ₦11m
    **can't enter, so the quest soft-locks.** [V, bug]
- **Venues** are 3D interiors with props and other players' avatars. Activities
  are menu cards, not object interaction.

### NPCs [V + I]
- NPCs exist but are thin. Example: "Mama Nkechi, Acquaintance, Food seller" at Amala Shitta.
- **"Gist with Mama" is a timed card** that ends with a single toast ("Mama told
  you everything happening on the street"). **No dialogue tree, no conversation.** [V]
- **[I] There is no AI in NPC behaviour or dialogue:**
  - No LLM or AI service calls appeared in network traffic.
  - No LLM-related strings appeared in the client bundle.
  - NPCs don't react to real-world events.
- Most "people" in venues are **real players**, not NPCs.

### Narrative [V]
- **"Lagos Stories":** a handful of short branching vignettes, each 2–3 choices
  long, plus Rep and ✨ rewards. Titles seen:
  - "Owambe Gatecrasher" (a Chief's daughter's wedding at Eko Hotels)
  - **"The Lost Bag"** (a bag of cash and a Chief's ID card under a danfo seat;
    return it, take it to the police, or keep it)
  - "Shrine Open Mic"
  - "Match Day Wahala"
  - "Pitch Night at CcHub"
  - "Big Man Night"
- **No story mode, no protagonists, no voiced or long-form writing.**
- **⚠ Overlap with our Up NEPA! seed:** "owambe at a hotel", "Chief" and "cash
  bag under a danfo seat" already exist there as short vignettes. See the
  differentiation notes in the story bible.

### Social [V]
- **Venue chat:** "Say something to the 6 players here…". Venue view caps at
  about 6 players, out of hundreds present.
- **Direct messages** with Requests for strangers, an "only friends" option and read receipts.
- **Contacts** and a **Family** system (relationships/"baes").
- **House invites** by link (fits 10 guests).
- **Referral links.**
- **"Lagos Gist":** a Twitter-like public feed with 280-character posts and
  Latest/Trending/Following tabs.
- **Player robbery:**
  - Tap a player in the same venue and "try your luck", for a maximum of ₦50k.
  - Police catch most attempts.
  - Victims can sue in a live "High Court" with lawyers.
  - Someone tried to rob this account during the session.
- **Reporting:** a ⚑ report button on profiles and jobs.
- **Moderation is visibly failing** [V]. Within 2 minutes on the public feed and job board I saw:
  - Sexual solicitation, including offers of explicit content for game money.
  - Real-money trading of game currency.
  - Advance-fee scams ("send ₦1k real money, get a billion").
  - Vote-buying posts.
  - Spam jobs.

### Job and gig marketplace [V]: already exists as "Hustle"
- Players hire players: Decorator, Cook, DJ, Driver, Bodyguard, Photographer,
  Tutor, Hustle (other), plus mason, electrician and plumber jobs for building houses.
- The fee is **held in escrow until the job is done**.
- There is a "Hustle rating", Find a pro / My jobs / Working tabs, Post a job,
  Hire directly, Ask (chat), Apply, and ⚑ report.
- **Problems:**
  - Many jobs sit at the ₦10,000,000 default with "Decorate my house".
  - Solicitation and scams are posted as jobs.
  - No visible filters beyond category.
  - No visible reviews on listings.
  - **Game money only**: it is not a real-world gig market.
- **Profile/CV** [V]:
  - Built **from game records, not typed in**: work history, education, criminal record.
  - Each section can be shown or hidden.
  - There are no player-entered skills, portfolio or bio.

### Civic system [V]: already exists and is popular
- **Offices:** Governor, Senator and President.
- **Weekly terms:** polls close Sunday 8pm.
- **Running for governor:**
  - Candidates pay a ₦50k campaign fee and post a slogan.
  - They can name a campaign manager.
  - There are 200+ candidates.
- **The winner:**
  - picks a city-wide **policy** (e.g. food subsidy: groceries 30% cheaper)
  - makes announcements
  - appoints a **cabinet** of commissioners (Finance, Works, Health, Transport)
  - earns a ₦25k/day allowance
- **Voting** is **in person at the Polling Unit** (Lagos Island), with "accreditation" and a live count.
- **Problems:**
  - Open vote-buying ("1B for who vote X").
  - Joke and offensive slogans.
  - A **real-world political campaign ad** bought as a lagoon "sea plot".
  - Sign-up needs no phone or email verification, so [I] multi-account voting is likely.

### Mini-games and rewards [V]
- **Whot! and Ludo:** real-time multiplayer at venue "Tables".
  - House rules are selectable (rollover, stacking).
  - Stakes range from Friendly to ₦10m.
  - The pot pays the winner minus ~5% rake. 4×₦1,000 pays ₦3,800.
  - There is a Hall of Fame.
  - Labelled "game money only".
- **Gem hunt:** a daily riddle clue that sends you to a venue; the next prize is ₦3,000 of game money.
- **Snooker Spot, Casino, LagosBet.**
- **[NO] No real-world prizes** (data, airtime) were seen anywhere.

### Settings [V]
- Night mode (Off/On/Auto)
- Camera auto-rotate
- **Data & battery saver** (Auto/On/Off; auto turns on with low battery or a slow network)
- **Lite graphics** (Auto/On/Off; skips 3D extras)
- Sound effects, music, free will, full screen
- Notifications, read receipts, who can message me, relationship privacy
- Change password, transaction PIN, log out everywhere, "someone stole my account" lock
- Replay walkthrough, contact support, report a security issue

**Missing:**
- No low/medium/high presets
- No frame-rate cap
- No shadows or draw-distance toggles
- No language options; English only, Pidgin used as flavour
- No accessibility options: text size, colour-blind modes and reduced motion are all absent
- **The activity cards are unlabeled for screen readers**

### Monetization [V]
1. Real-money game-money packs via Flutterwave.
2. Paid timed billboards in the 3D city ("YOUR AD HERE").
3. "Sea Plots": a pixel-grid ad mosaic on the lagoon.
4. Brand partnerships:
   - A fintech's promo on the phone home screen, pointing to a real company's IPO.
   - An Afrobeats artist's album rollout on billboards.
   - A food-delivery brand app on the phone.
5. Third-party "NEW" apps on the phone: Meetumo, PopOut, HANDI, Heala, Nollywood, Bet Tips and others.

They state "no ad trackers".

### Art and audio [V/I]
- **3D low-poly**, isometric camera.
- [I] The world uses Kenney stock kits (paths `commercial/`, `suburban/`, `pirate/`, `car/`).
- Characters are GLB files per outfit, with avatar options for skin, hair (low
  cut, locs, braids…), outfit (Ankara, Adire, Aso-oke…) and body.
- Simple idle animations.
- The UI is clean and modern (Fredoka and Plus Jakarta Sans fonts, emoji icons).
- Music plays by default and has a toggle; I didn't evaluate it in detail.

### Technical [V]
- Next.js (Turbopack) and React, Three.js r186 on WebGL2.
- PWA: manifest with `lang en-NG` and a service worker.
- **JS payload:** ~109 chunks, ~7 MB uncompressed after visiting a few screens.
- **Backend:** REST JSON plus HTTP polling.
  - `PUT /api/save` and `POST /api/world` every ~2s.
  - `GET /api/gov`, `/api/politics` and `/api/version` every ~4s.
- **Data usage, normal play** [V]:
  - **Repeat visit at mobile size:** ~54 KB in the first 25s. The service worker
    caches the JS and models.
  - **In-world idle at mobile size:** **~8 KB per 40s (~0.7 MB/hour)**. This is
    lean and a real strength.
- **⚠ Data leak after opening the Lagos Gov app** [V measurement; I cause]:
  - After the elections app had been opened, the client kept polling
    `/api/politics` every ~4s even with the phone closed.
  - Each poll re-downloads the full candidate list: ~547 KB uncompressed, ~194 KB brotli.
  - Measured **~3.9 MB in 70 seconds**. That projects to **~200 MB per hour**
    until reload [I extrapolation].
  - [I] This is a polling-cleanup bug, and costly on Nigerian prepaid data.
- **Mobile layout** [V]:
  - Compact HUD.
  - A **context "next need" button**: the lowest need plus one-tap fix, e.g.
    "Hygiene 0% → Wash". This is good UX.
  - Bottom nav: Home / Buy / Map / Phone.
  - The title screen offers "Continue" or "New life".
- Server-side saves (`/api/save`); there is no visible offline mode.

## 3. Cultural authenticity
**Gets right** [V]:
- Real Lagos landmarks and food (amala, gbegiri, ewedu, ofada, zobo).
- Danfo, keke and okada fares.
- Whot! with Naija house rules.
- NEPA, generator and solar.
- Owambe season, Balogun, CcHub, Shrine.
- Light Pidgin in moodlets.
- Ankara, Adire and Aso-oke outfits.
- Abuja and PH content.

**Generic or wrong** [V/I]:
- The city is a stock kit that doesn't look like Lagos.
- Travel skips the defining Lagos experience: go-slow, conductors, agberos, road wardens.
- NPCs have no voice.
- Pidgin is sprinkled, not spoken.
- No Yoruba, Igbo or Hausa.
- No local markets as gameplay.
- No POS agent culture, ajo/esusu, aso-ebi pressure, church/mosque social life or
  relatives' "small requests".

**Real names used:**
- Real venues and brands: Eko Hotels, Quilox, The Palms, a real food-delivery brand, a fintech.
- A real agency (EFCC) and real football clubs.
- [I] This creates trademark and defamation exposure that we avoid with fictional names (brief requirement).

## 4. Bugs and rough edges [V]
- **Story soft-lock:** The Lost Bag sends a ₦11m player to a ₦1bn-gated venue.
- **Panel clicks unreliable:** several taps on activity cards didn't register on
  the first try (desktop).
- **Accessibility:** activity cards are buttons with no labels.
- **Map loading:** "Loading map… 0%" stalls on scene switches; the scene renders
  blank for a few seconds.
- **Scale beats content:** the venue view caps at ~6 visible players out of hundreds present.
- **Hyperinflation makes rewards meaningless:** a daily prize of ₦3,000 versus
  players holding billions.
- **Moderation:** see Social, above.

## 5. User flow map (observed)
```
Landing (live 3D city, cookie banner, live counters)
  ├─ Sign up (name, @username, password, optional email, DOB, 18+ & Terms) ─┐
  └─ Log in ────────────────────────────────────────────────────────────────┤
                                                                            ▼
City HUD: clock · mood · visits · online · wallet(top-up) · daily reward ·
          gem hunt · needs bar · bottom nav [Home | Buy | Map | Phone]
  ├─ Map → pick venue → pick transport → (fade) → Venue
  │     Venue: activity tabs → cards (timer, ₦ cost) · venue chat · People · Tables
  ├─ Sim panel: Profile/CV · Needs · Goals(Dream, Wishes, Perks, Courses) ·
  │             Skills · People · Career · Settings
  ├─ Today's Hustle: streak · 3 missions · Lagos Stories (branching vignettes)
  ├─ Phone (40+ apps): Jobs · Messages · Hustle(gig board) · Lagos Gist(feed) ·
  │     Lagos Gov(elections) · LagosBet · Bus Co. · Bank/Invest · Police/Court ·
  │     Houses/Cars/Shops · partner apps
  └─ Wallet → top-up packs (Flutterwave)
```

## 6. Session 2 checklist (retention; to do)
- [ ] Daily reward claim flow and streak behaviour
- [ ] Offline progress: do needs decay offline? Do businesses (Bus Co.) pay out?
- [ ] Notifications: blocked in this browser; check what is promised
- [ ] Replay the walkthrough to assess onboarding
- [ ] Mobile viewport pass: controls, layout, data use with Lite graphics on
