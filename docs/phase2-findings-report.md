# Naija Street Life — Phase 2 Findings Report

**Date:** 2026-10-14
**Covers:** research on the competitor at lagoslife.app ("the reference game"),
the Jev AI investigation, and the next decisions.
**Detail and evidence:** [research notes](research/01-reference-game-notes.md).
**Companion deliverable:** [Story Bible](story/story-bible.md).
**Labels:** **[V]** verified by play or network. **[I]** inferred.

---

## 1. What the reference game is (confirmed by playing)
It is a **free, browser-based, massively shared Sims-style life game**:
- A Next.js PWA with a Three.js 3D isometric world.
- About **55,000 players online at once** in one shared Lagos. Abuja and Port
  Harcourt are extra maps. [V]

**How you play:**
1. Pick a venue on a small map.
2. Pick a transport mode. That's a fare and a fade, not a ride.
3. Tap activity cards. Each runs a timer of a few seconds and refills one of six
   Sims-style needs. [V]

**Progression:**
- Careers with ranks and 1-hour shifts, and nine skills.
- A Lifetime Dream, Wishes and Perks.
- Daily missions with a 7-day streak, a daily riddle hunt, and "Lagos Rep" XP. [V]

**The big draw is other players:**
- Venue chat and a public social feed ("Lagos Gist").
- DMs, house parties and family/relationships.
- A player-to-player gig board ("Hustle").
- Weekly player elections for Governor, Senator and President.
- Whot and Ludo tables for game-money stakes.
- Robbing other players, then suing them in a live court. [V]

**Money:**
- Real-money packs of game money via Flutterwave.
- Paid in-world billboards, buyable ad tiles on the lagoon, and brand partnerships. [V]

**Gaps:**
- **No story mode.** There's only a handful of 2–3-choice "Lagos Stories" vignettes. [V]
- **NPCs are thin and scripted.** "Gist with Mama" is a timer and a toast. There's no
  AI and no real-world news. [V/I]

## 2. Required-features checklist

| # | Naija Street Life feature | Reference game | What they have / don't have |
|---|---|---|---|
| 1 | Job/gig marketplace | 🟡 **Partly** | **Has:** a player-to-player gig board with escrow, categories, a Hustle rating, Ask/Apply and a report flag. **Lacks:** filters, visible reviews and fraud checks. It's full of spam, scams and sexual solicitation, and it's **game money only**, with no real-world gigs. |
| 2 | Profiles and skills | 🟡 **Partly** | **Has:** an auto CV built from game records (work, education, criminal record) with visibility toggles, plus nine in-game skills that gate careers. **Lacks:** player-entered skills, portfolio, bio or experience, and links to real work. |
| 3 | Graphics settings | 🟡 **Partly** | **Has:** Lite graphics, Data & battery saver (both Auto/On/Off, with auto-detect on slow networks), night mode and camera rotation. **Lacks:** low/medium/high presets, toggles for shadows, effects and draw distance, an FPS cap and accessibility options. |
| 4 | Polls and elections | 🟢 **Has, but flawed** | **Has:** weekly Governor/Senator/President elections with a ₦50k fee, slogans, campaign managers, real policy effects, a cabinet, an allowance, and in-person voting with "accreditation". **Problems:** open vote-buying, likely multi-accounting (no phone/email verification), a real-world political ad sold in-game, and no general-purpose polls. |
| 5 | Games that win data/airtime | 🔴 **Lacks** real prizes | **Has:** Whot/Ludo stake tables, LagosBet (sports, roulette) and a gem hunt, all for **game money only**. **Lacks:** any data or airtime prizes. Its gambling on purchasable currency is a regulatory grey zone. |
| 6 | AI-driven NPC decisions (Jev) | 🔴 **Lacks** | NPCs are flavour labels and toasts. No AI calls were seen in traffic or the bundle. |
| 7 | News API (real events) | 🔴 **Lacks** | It has **scripted fictional city events** (flooding, fuel scarcity, a central bank rate hike, owambe season, Apapa gridlock) that change the game. There's no real news. |
| 8 | NPCs talking about the news | 🔴 **Lacks** | No NPC conversation exists at all. |
| 9 | Story mode, 3 protagonists | 🔴 **Lacks** (⚠ overlap) | No story mode. **But** its vignettes "The Lost Bag" (a Chief's cash under a danfo seat) and "Owambe Gatecrasher" overlap our premise. See §6 and the Story Bible. |

## 3. Strengths to keep or match
1. **The shared-world feeling.** Every player is in the same Lagos, with live counts,
   real people in every buka, and elections that matter. This is the main thing
   people come back for.
2. **Very lean on data in normal play [V].**
   - About 0.7 MB/hour idle at mobile size.
   - The service worker caches assets, so repeat visits cost about 54 KB.
   - Lite/Data-saver modes switch on automatically.
   - We must match or beat this.
3. **Tight, readable core loop.** Needs, then one tap, then a short timer, then
   visible progress. The mobile **"lowest need → one-tap fix"** button is excellent UX.
4. **Elections with real consequences:** policies change prices, there's a cabinet,
   and voting is in person at a polling unit. It's an emergent drama engine.
5. **Escrowed player gigs and a CV built from game records.** That's the right
   foundation for features 1 and 2, but it needs to be done properly.
6. **Cultural set dressing:**
   - Real food menus, danfo/keke/okada fares, and Naija Whot house rules.
   - NEPA with generator, solar and inverter upgrades.
   - Ankara, Adire and Aso-oke outfits, and light Pidgin.
7. **Clear account security:** transaction PIN, log out everywhere, and an
   "account stolen" lock.

## 4. Weaknesses and gaps (ranked by how much fixing them matters to players)
1. **Trust and safety collapse [V]:**
   - The public feed and gig board are flooded with sexual solicitation, offers to
     sell game money for real money, advance-fee scams and vote-buying.
   - It's 18+ only, yet unsafe, and it drives away exactly the players who would pay.
2. **Broken economy [V]:**
   - Game money trades on the black market at thousands of times below the official
     top-up rate.
   - Players hold billions, so the ₦3,000 daily prizes and ₦200 meals mean nothing.
   - It undercuts their own revenue and makes progress feel fake.
3. **No story, no characters, no humour engine.** The writing is limited to one-line
   toasts and 3-choice vignettes, and a quest can soft-lock (The Lost Bag needs a
   ₦1bn-gated venue) [V].
4. **Lagos is a menu, not a place.**
   - Travel is a fade; there's no go-slow, conductor, agbero or road warden.
   - The city is a stock-kit diorama [I].
   - NPCs have no voices or opinions and don't react to anything.
5. **Election integrity [V/I]:**
   - Cheap accounts and open vote-buying.
   - A real politician's ad was sold on the lagoon.
   - Joke candidates bury serious ones (200+ on the list).
6. **Data leak and performance edge cases [V]:**
   - The elections screen keeps polling about 194 KB every 4 seconds after it's
     closed, roughly 200 MB/hour until reload.
   - The map stalls at "Loading map… 0%".
   - Taps don't always register.
7. **Accessibility [V]:** activity cards have no screen-reader labels, and there are
   no text-size, colour-blind or reduced-motion options. It's English-only.
8. **Legal exposure [I]:**
   - Real brand, venue, agency (EFCC) and club names.
   - Sports betting on real fixtures.
   - Gambling with currency bought for real money.
9. **Onboarding (not verified).** This account was pre-existing, so I didn't see
   the first-time flow. It's on the Session 2 checklist.

## 5. Opportunities: how Naija Street Life wins
**Positioning:** *"The other one is Lagos as a menu. Ours is Lagos as a story you
can walk into: funny, safe, and it pays you back in real data."*

1. **A story mode no one else has.**
   - "Up NEPA!" gives three playable heroes, a 4-act plot and four endings.
   - Missions **are** the life-sim systems: danfo driving, ajo collection, POS gigs,
     content shoots.
   - Their best content is a 3-choice vignette; ours is a sitcom-length campaign.
2. **Lagos you can feel, in 2D.**
   - Hand-painted art in The Omins' style, seen from above at an angle.
   - Danfo rides are *played*, with go-slow, conductor combos and passenger arguments.
   - Hand-painted districts make it look unmistakably like Lagos, not a stock kit.
   - It's lighter than 3D on low-end Androids (decision D-001).
3. **NPCs with opinions.**
   - Jev picks *what* an NPC does: buy, vote, react, haggle.
   - A small text model (or a pre-written bank) supplies *what they say* (see §7).
   - NPCs argue about today's fuel price or match result, with guardrails.
   - This is what makes "real friends" include the NPCs.
4. **Safety as a feature.**
   - Phone-verified accounts for civic, marketplace and prize features.
   - Pre-moderation of public posts using Jev classifiers.
   - Scam-pattern detection ("send real money").
   - Verified vote-buying penalties, and no real political ads.
   - Market it: "the Lagos game your younger cousin and your aunty can both play".
5. **A sound economy.**
   - Game money can't be traded (no player-to-player cash transfers, or capped and
     taxed ones).
   - Strong money sinks, and prizes priced against a stable economy.
   - This makes every achievement and reward meaningful.
6. **Real rewards that are legal.**
   - Skill-based mini-games (visa interview, ajo collection, danfo conversation)
     that pay **data and airtime**.
   - Free entry, no purchase required.
   - Daily caps and anti-cheat, delivered by a Nigerian airtime/data API.
   - This needs a lawyer's sign-off before launch; details come in Phase 3.
7. **A real-world gig board.**
   - Verified skills and a portfolio, ratings and reviews, and escrow through a
     licensed payment provider.
   - Keep it **separate from game money**.
   - This is a genuine product the reference game doesn't attempt.
8. **Cheaper on data.**
   - Match their ~1 MB/hour idle.
   - Use push and websocket deltas instead of re-downloading full lists.
   - Stream districts as small WebP/AVIF image atlases, and set a hard data budget
     per session.

## 6. ⚠ Story overlap with the reference game
The reference game already has short vignettes about **a Chief's cash bag under a
danfo seat** and **gatecrashing a Chief's daughter's owambe at a hotel**. These are
common Lagos tropes, not anything they can own, and we copy none of their text.
Even so, players will notice. The Story Bible differentiates our version by:
- making the bag the spine of a **three-hero ensemble**, not a moral-choice popup
- making it a **campaign war chest stolen in a NEPA blackout**, with the Chief as a
  recurring villain
- having **our own fictional Chief** ("Double Chop", not their name)
- staging the owambe as the **site of the crime**, not a gatecrash

**Recommendation:** keep the seed as written. Avoid "lost bag" and "gatecrash"
wording in our marketing.

## 7. Jev AI: what it actually is
**Sources:** TypeSafe's own docs, read 2026-10-14: [intro](https://docs.typesafe.ai/introduction),
[quick start](https://docs.typesafe.ai/introduction/quickstart), [models](https://docs.typesafe.ai/models.md),
[known weaknesses](https://docs.typesafe.ai/model-jaggedness/jev-1.13.md).

**What it is** [V from docs]:
- "Jev" is **TypeSafe AI's "System One" decision model**, version `jev-1.13.0`.
- You send a **state** (text or JSON) plus typed **questions**:
  - **Choice:** pick one of N options.
  - **Score:** a graded scale.
  - **Noul:** true/false as a 0–1 value.
- It returns answers with **probabilities and confidence**.

**API details:**

| | |
|---|---|
| Endpoint | `POST https://api.typesafe.ai/v1/systemone` |
| Auth | Bearer key |
| SDKs | JS (`@typesafe-ai/sdk`), Python |
| Context | 64k tokens per request |
| Rate limits | 80 requests/s, 100k tokens/s (dynamic) |
| Price | **$0.042 per million input tokens; output is free** |
| Latency | Vendor marketing claims ~0.1s; unverified |

**What it's good for:**
- NPC choices from a legal-action list: buy, vote, react, haggle, accept a gig.
- Classifying chat and job posts for moderation.
- Tagging and filtering news by topic and sensitivity.
- Fraud-signal scoring.

**What it can't do:**
- **It doesn't generate text.** NPC dialogue, news summaries and banter need a
  separate text model (e.g. Claude) or pre-written line banks.
- Weak at maths, counting and dates. Those must be computed in code.
- Biased toward the first option, so options must be shuffled.
- English is its best language. Pidgin, Yoruba, Igbo and Hausa accuracy is
  **untested**, and we need our own evaluation.
- It's in **early access**, and limits "can change without notice".
- No official pricing page and no stated data-retention terms. Ask TypeSafe.

**Rough cost** [I]:
- An NPC decision with a ~1,500-token state costs about $0.00006.
- One million decisions cost about **$63**.
- Cost isn't the constraint; rate limits and latency are. We'd batch, cache and
  fall back to rules (Phase 3).

**Assumption to confirm:** I've assumed "Jev AI" in the brief means this TypeSafe
product. It's the only match I found.

## 8. Open questions only you can answer
1. **Jev:** is TypeSafe's Jev the one you meant? Do you have an account or early
   access? And may we add a separate text model (I'd suggest Claude) for NPC
   dialogue and news summaries, since Jev can't write text?
2. **Real money:**
   - Will the gig marketplace handle **real naira** (escrow through a licensed
     provider such as Paystack or Flutterwave, which needs a registered Nigerian
     company), or start with game money only?
   - Will we sell game currency at all?
3. **Age rating:** 18+ like theirs, or 13+/16+ with a safer default? This changes
   chat, the marketplace, prizes and the election rules.
4. **Verification:** may we require **phone (OTP) verification** for voting, posting
   gigs and winning prizes? It costs money per SMS and adds friction, but it's the
   main anti-fraud tool.
5. **Prize budget:** what monthly naira budget for data and airtime prizes? And do
   you have a Nigerian company and lawyer for promotion/lottery rules?
6. **Real places:** the content rules say all places must be fictional, but the seed
   uses real areas (Lekki, Yaba, Ketu). My proposal: **real neighbourhoods are OK,
   but every business, venue, agency and person is fictional.** Agree?
7. **Platform:** web and mobile web only at launch, or also wrap the game as an
   Android app (Play Store) later?
8. **Team:** who paints the art (an in-house artist, contractors, or me producing
   placeholder art first)? And who does the native-speaker slang review?
9. **Languages:** English and Pidgin at launch? Add Yoruba, Igbo and Hausa interface
   options later?

## 9. Research status and honesty notes
**Done:**
- ~35 minutes of play on a **pre-existing** account (desktop), plus a phone-size check.
- Network and data measurements.
- A keyword-only scan of the client code.
- Jev docs reviewed.

**Not done yet** (Session 2, later today or tomorrow):
- Daily-reward claim and streak.
- Offline progress.
- Notifications.
- First-time onboarding (via "Replay walkthrough").
- Low-end Android device testing.

I did not create accounts, chat with players, spend real money, or copy assets, code or text.
