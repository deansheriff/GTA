# Up NEPA! — Abilities and Progression Spec (Story Deliverable 3)

*Draft v0.1, 2026-10-14 (M0). Numbers are starting values for playtest tuning.*

## 1. Shared progression
**Skills** (shared with the player profile system, proposal F2):

| Skill | Main hero | XP sources |
|---|---|---|
| Driving | Tunde | Fares delivered, chases survived, clean go-slow runs |
| Cooking | Aunty Boss | Plates served, catering gigs |
| Haggling | Aunty Boss | Negotiations won, ajo collections |
| Filming | KC | Clips captured, Go Live sessions |
| Charisma | all | Dialogue checks passed |
| Composure | KC | Interview and debate mini-games |

**Levels:**
- Each skill runs 1–10. XP to the next level = `100 × level^1.5`, rounded.
- Each level gives a small passive bonus. For example, Driving +3% handling per level, and Cooking +4% plates per minute.

**Story money (₦s):**
- Pays for upgrades (bus repairs, power banks, aso-ebi).
- It doesn't carry into free roam until the credits.

**Relationship (Rel 0–100 per pair):** shown in the Family Meeting chat header.

| Rel | Effect |
|---|---|
| ≥ 60 | Co-op assists in missions; needed for Ending A |
| < 30 | Unlocks "the silent treatment" switching messages |

**Ability tiers:** unlocked by story beats (see the mission list), never by grinding. Free-roam play only upgrades *passives*.

---

## 2. Tunde — Blood Pressure (BP)

### BP meter
- **Range:** 0–100. Starts each mission at 20.

| BP | Effect |
|---|---|
| 0–39 | Calm: normal handling, passengers relaxed |
| 40–79 | Heated: +10% ramming force, horn scares NPCs further; camera slightly tighter |
| 80–99 | Boiling: +20% ramming force; steering jitter ±4°; passengers' moods drop 2× faster |
| 100 | **Wahala Mode**: Tunde stops the bus to argue for 6 seconds while the timer runs. Passengers either join in (comedic assist) or leave without paying |

**What raises BP:**

| Event | BP |
|---|---|
| Stopped in go-slow | +2/sec |
| Road warden encounter | +15 |
| Overtaken by a keke | +8 |
| "I no get change" | +10 |

**What lowers BP:**

| Event | BP |
|---|---|
| Fuji on the radio | −1/sec |
| Argument won | −15 |
| Agege bread (item) | −25 |
| Aunty's pepper soup (item) | −40 |
| Going 5 seconds without braking | −5 |

**Upgrades:** BP control +1 (from missions 1.4 and 2.6) cuts BP gains by 10% each.

### Go-Slow Whisperer (active; cooldown 45s)

| Tier | Unlock | Effect |
|---|---|---|
| 1 | 1.1 | Time slows to 50% for 4s; hidden bypasses within 150 m light up |
| 2 | Act 2 free-roam milestone (50 fares) | 6s; bypass range 300 m; shows police and warden positions |
| 3 | 2.3 | 8s; can open **one** "impossible" shortcut per mission (through a market, under a bridge) |

### Conductor Combo (active, via Sule; chain calls inside a 3s window)
Calls:
- "Enter with your change!" (calm passengers)
- "Hold door!" (passengers brace; less damage)
- "Duck!" (avoid a search)
- "Owambe guests, VIP!" (pass checkpoints)
- "Last bus!" (rush boarding)

| Tier | Effect |
|---|---|
| 1 | 1 call per use |
| 2 | Chains of 3 calls; a correct sequence (e.g. Hold door → Duck → VIP) gives a bonus effect |
| 3 | Passengers can vote *with* Tunde: in chases, he gets +1 vote weight per successful call |

### Passive: Philosopher of Traffic
Every 10 minutes of driving, Tunde says a traffic proverb (from the line bank) that grants −10 BP.

---

## 3. Aunty Boss — Aunty Aura

### Aura meter
- **Range:** 0–100. **Persists** between missions; it's her reputation.

| Aura | Effect |
|---|---|
| 0–29 | Ignored: NPCs interrupt her; haggle results −15% |
| 30–69 | Respected: normal |
| 70–89 | Feared: The Stare lasts +50%; shopkeepers give an automatic 10% discount |
| 90–100 | **Legend**: some NPCs confess unprompted; henchmen hesitate before approaching |

**What raises Aura:**

| Event | Aura |
|---|---|
| Debt collected | +2 |
| Feeding someone in need | +3 |
| Keeping a promise | +5 |
| Argument won | +4 |

**What lowers Aura:**

| Event | Aura |
|---|---|
| Public disrespect left unanswered | −5 |
| Broken ajo promise | −15 |
| Seen begging | −10 |
| KC's secret discovered (2.2, caught) | −20 |

### The Stare (active; hold to focus; cooldown 30s)

| Tier | Unlock | Effect |
|---|---|---|
| 1 | Prologue | A single NPC freezes for 3s × (1 + Aura/100). Dialogue option: "Confess" |
| 2 | 2.1 | Works on groups of up to 4 in a cone; adds the "Hand it over" option |
| 3 | Act 3 (Rel ≥ 60 with KC) | Can be broadcast through KC's Go Live: everyone watching the stream freezes (finale use) |

**Immune:** her own mother, babies, and Engineer Bayo ("I'm a professional").

### Ajo Network (active; daily charges)

| Tier | Unlock | Effect |
|---|---|---|
| 1 | 1.2 | Trusted keke fast travel, 1 per in-game day |
| 2 | 2.5 | Plus hideouts in 6 market stalls: chases end on entry; 2 per day |
| 3 | Act 3 | Plus intel calls: reveal mission targets on the map; free food restores all needs; 3 per day |

### Passive: The Ledger
- Aunty remembers every debt in the game, both story and free-roam (proposal F1 gigs).
- Debtors on screen get a ₦ tag.
- **Collecting is optional, but she will comment.**

---

## 4. KC — Hype and Phone Battery

### Battery (0–100%)

| Drain | Rate |
|---|---|
| Base | −1% per 20s |
| Filming | −1% per 4s |
| Go Live | −1% per 2s |
| Gist | −3% per use |

| Recharge source | Effect | Cost / catch |
|---|---|---|
| Canteen socket (after 2.1) | +2% per second | Free; ask Aunty first |
| Generator owner | +40% | ₦200 plus a 20s chat |
| Power bank | +50% | Item |
| NEPA | +1% per second | Only while the light is on, which is random |

At **0%**, abilities are disabled and KC "narrates to strangers": a comic voice line, and nearby NPCs move away.

### Hype meter
- **Range:** 0–1,000 followers-gained-today scale, shown as a fire icon.

| Hype | Effect |
|---|---|
| ≥ 200 | Bouncers let KC in |
| ≥ 500 | Crowds gather when he Goes Live |
| ≥ 800 | Brand-deal side missions unlock |

| Event | Hype |
|---|---|
| Good clip | +10–40 |
| Go Live peak | +50 |
| True gist confirmed | +30 |
| Flop | −20 |
| False gist debunked | −150, and **Trust −1** |

**Trust (0–5, hidden):** below 3, gists spread 50% slower and NPCs say "na lie again".

### Go Live (active; drains Battery fast)

| Tier | Unlock | Effect |
|---|---|---|
| 1 | 1.3 | Nearby crowd reacts: rally (follows and blocks enemies) or turns on a target, picked with a 2-option prompt |
| 2 | Act 2 milestone (Hype 500) | Crowds part for KC ("content creator coming through"); henchmen hesitate on camera |
| 3 | Finale | Broadcast mode: every phone in the stadium plays the stream |

### Gist (active; 3 per in-game day)

| Tier | Unlock | Effect |
|---|---|---|
| 1 | Act 2 start | Seed a rumour about a fictional NPC or event; it spreads along one network (danfo, market or WhatsApp) |
| 2 | 2.7 | Two networks at once, plus a "receipt" attachment: gists backed by evidence can't be debunked |
| 3 | Act 3 | Gists can shift NPC voting blocs in the election simulation (true gists only; false ones backfire) |

**Hard rule:** Gist targets only fictional story entities. It is never wired to real news or real people (Bible §8.3).

### Passive: Signal Loss
- At dramatic beats there's a 15% chance the stream freezes for comedic effect.
- It never happens in timed segments, so it never costs the player a fail.

---

## 5. Switching and off-screen life
- **Switching** is free in free roam and scripted in co-op missions.
- Each switch plays a 3–6 message Family Meeting chat. Messages come from the deliverable-5 bank and depend on Rel and recent events.
- **Off-screen event roll** happens on switch-back after ≥ 2 in-game hours away. One weighted event per absent hero:

| Event | Weight | Effect |
|---|---|---|
| Danfo towed by LARDO | 10 | ₦s −3,000 to retrieve; BP +20 |
| Aunty started a market dispute | 10 | Mini-quest to settle it; Aura ±5 |
| KC went viral for the wrong reason | 10 | Hype ±100 (coin flip); new nickname |
| Quiet day | 50 | Small ₦s from side hustles |
| Relative's "small request" | 20 | Choose to pay ₦s or dodge the call; Rel effect |

- No event can break story state; all are cosmetic or economic.

## 6. Tuning and telemetry (playtests in M1–M2)
**What we track:**
- time per mission
- fail points
- ability use rates
- BP time-in-zone
- Battery 0% occurrences
- Hype curve
- ending distribution

**Targets:**
- Battery hits 0% in no more than 1 of 4 KC missions.
- Wahala Mode triggers at most once per Tunde mission on average.
