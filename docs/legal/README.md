# Legal and store compliance pack (M7) ⚖️

Everything here is a **draft prepared for the owner's lawyer**. None of it is legal advice.

| Document | Where |
|---|---|
| Privacy policy | `apps/server/src/legal/privacy.md`, served at `https://game.YOUR-DOMAIN/privacy` |
| Terms of use | `apps/server/src/legal/terms.md`, served at `/terms` |
| Google Play Data safety answers | [data-safety.md](data-safety.md) |
| Content rating (IARC) questionnaire answers | [content-rating.md](content-rating.md) |
| Lawyer checklist | below |

## What the game already does

- **Age gate on first launch.** Players under 18 get safe mode: the story and offline play work; chat, gigs, profiles, voting, challenges and NPC chat are hidden.
- **Data rights (NDPA).** The in-game Profile lets players download their data (`GET /api/me/export`) and delete their account (`DELETE /api/me`). Election receipts stay in the chain but are anonymised.
- **Telemetry.** It is opt-in: a first-run question, changeable in Settings. It is anonymous, uses whitelisted events, and has no device identifiers.
- **Money features are off by default.** Prizes (`prizes_enabled`), the prize pool (₦0 by default) and real-money gigs (`real_money_enabled`) are switched in the admin console. With no provider configured, prize tickets are never fulfilled.
- **Phone numbers** are stored only as a keyed hash.

## Lawyer checklist (from proposal F5 and F1)

1. Is a free-entry skill challenge a "lottery" or "gaming" under each relevant state's law? Lotteries are state-regulated after the Nov 2024 Supreme Court ruling.
2. **FCCPC sales promotion registration.** The draft *Sales Promotion (Amended) Regulations 2026* was published 30 Sep 2026, with comments due 20 Oct 2026. It covers registration fees, penalties, and registering AI use in promotions.
3. The age-verification method. The game currently uses a self-declared birth year plus phone verification.
4. Consumer protection: T&Cs, a complaints process, and prize-delivery duties (FCCPA).
5. Tax on prizes.
6. **NDPA 2023 + GAID 2025:**
   - a DPIA for profiling (moderation, anti-fraud)
   - a DPO
   - possible registration as a data controller of major importance
   - consent records (telemetry consent is stored on the device; add server-side records if required)
7. NCC rules on SMS/OTP sending (DND, sender ID).
8. **Real-money gigs:**
   - a CAC company, TIN and corporate account
   - a CBN-licensed escrow or payment partner (or split-on-capture)
   - KYC for payouts
   - VAT on fees
9. **News use:** each outlet's terms for headline-and-link use (`NEWS_FEEDS`).
10. Music licensing for any soundtrack (M8).
