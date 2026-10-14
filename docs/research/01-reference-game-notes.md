# Naija Street Life — Reference Game Research Notes

Session 1 · 2026-10-14 · Logged out, landing page only. NOT yet played.

Label key: **[Verified]** = observed directly. **[Inferred]** = reasoned from evidence, not confirmed.

## Status
- Blocked at account creation. The assistant cannot create accounts or set
  passwords. The owner must create a throwaway account in the in-app browser
  pane, then hand over so play-testing can continue.
- Sign-up form [Verified]: name, username, password (min 8), optional email
  ("we never send you codes"), date of birth, and an 18+ / Terms checkbox.
  No CAPTCHA or email verification was visible before submitting.

## Tech [Verified unless marked]
- Next.js (Turbopack build) web app with a PWA manifest (`lang: en-NG`,
  standalone display) and an active service worker.
- WebGL2 canvas running Three.js r186.
- Character models are separate GLB files per outfit
  (`/models/chars/m_party.glb`, `f_party.glb`, `m_casual.glb`, ...).
- World textures are at paths like `/models/world/{commercial,suburban,pirate,car}/Textures/colormap.png`.
  **[Inferred]** These paths match the naming of Kenney's free CC0 asset kits
  (City Kit Commercial/Suburban, Pirate Kit, Car Kit), so the world is likely
  built from stock low-poly kits rather than custom art.
- Landing page: about 250 resources and ~960 KB transferred while logged out,
  before any gameplay.
- Public JSON endpoints: `/api/gov`, `/api/ads`, `/api/sea`, `/api/homes?map=1`, `/api/version`.
- Their manifest's tagline: "Sims, but make it Eko. A life-sim set in Lagos, with real players."

## Landing screen [Verified]
- Isometric low-poly city with emoji map pins for 35 named places.
  - Some are real Lagos venues/brands: Afrika Shrine, Amala Shitta, CcHub,
    Freedom Park, Quilox, Eko Hotels, The Palms, Marina Towers, UNILAG,
    Jibowu Park, Mako, Ikoyi Golf Club.
  - Others are generic: Market, Church, Mosque, Polling Unit, High Court,
    Casino, Snooker Spot, Police Station, Hospital.
  - "OBO · Coming soon" is also listed.
- Header shows live counters: "56k online" and "40972k visits".
- Cookie banner offers "Essential only" or "Accept" and states "no ad trackers".

## Civic system: already exists [Verified via /api/gov]
- A player-elected "Governor" serves fixed terms (currently term 2; the term 3 election is open).
- Candidates are players with a slogan and an avatar look. Vote counts are public (the governor won with ~192k votes).
- The governor sets a `policy` (currently "food") and posts a public announcement.
- Candidate slogans are joke promises ("Free 50 Billion to everyone who votes for me").
- **[Inferred]** Fraud and multi-account controls are unknown. Account creation is
  cheap (no email, no phone, no CAPTCHA seen), so there is likely multi-account
  voting risk. To be verified in play.

## Monetization [Verified]
- Paid in-world billboards ("YOUR AD HERE"). Ad slots run on timers (`endsAt`) and link out to real businesses.
- "Sea Plots": players buy pixel-grid ad tiles on the lagoon, like a million-dollar-homepage.
  Live tiles include a real-world political campaign ("... for Lagos State Governor").
- Brand partnerships: billboards for a fintech and an Afrobeats artist's album rollout.
- "400 homes" counter, likely a player housing system.

## Gaps visible already [Inferred, to verify in play]
- No story mode is visible anywhere on the landing page.
- No job/gig marketplace is visible from the outside.
- A real political campaign ad is live in-game, which shows moderation risk for civic content.
- The map is landmark pins on a stock-kit city; Lagos texture and density may be thin.

## Art reference: The Omins (Steam app 2397750) [Verified]
- Developer: TemesaGames. A colony-sim/RTS in a top-down 3/4 view with hand-painted
  2D art: chunky readable silhouettes, warm saturated palette, soft painted
  ground textures, cute stylized characters.
- **Decided (owner, 2026-10-14):** 2D in The Omins' style, smooth, no 3D in the
  browser. See `docs/decisions.md` (D-001).

## Still to research once logged in
Core loop, needs/stats, jobs, economy, time, events (NEPA, traffic), travel,
NPC behaviour/AI, chat and friends, moderation, mini-games and rewards, settings,
onboarding, retention on a second session, per-session data usage, and bugs.
