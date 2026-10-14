# Google Play: Data safety form answers (draft) ⚖️

These are prepared from what the code actually does as of M7. Re-check them before each release.

**Does your app collect or share any of the required user data types?** Yes. It collects data and does not share it with third parties for their own purposes. Processors such as hosting, SMS and AI act on our behalf.

**Is all user data encrypted in transit?** Yes. The game uses HTTPS and WSS through Cloudflare. Local and LAN development servers are the only exception.

**Do you provide a way for users to request that their data be deleted?** Yes. In the game, Profile → Delete my account (`DELETE /api/me`), or by email.

| Data type | Collected | Shared | Optional? | Purpose |
|---|---|---|---|---|
| Personal info › Name (display name) | Yes | No | Required for online play | App functionality |
| Personal info › Phone number | Yes, as a keyed hash only. The raw number passes through to send the OTP. | No | Optional | Account management, fraud prevention |
| Personal info › Other info (birth year) | Yes | No | Optional | Fraud prevention / compliance (18+ for prizes) |
| Messages › Other in-app messages (chat, DMs, NPC chat) | Yes | No | Optional | App functionality, safety |
| App activity › In-app actions (missions, mini-games) | Yes, anonymous and opt-in | No | Optional | Analytics |
| App activity › Other user-generated content (gigs, profile, polls, votes) | Yes | No | Optional | App functionality |
| App info and performance › Crash logs, Diagnostics (fps buckets) | Yes, anonymous and opt-in | No | Optional | Analytics |
| Device or other IDs | **No.** The telemetry ID is a random per-install value, not a device ID. | — | — | — |
| Location | **No** | — | — | — |
| Financial info | **No.** Prize/payment features are off; revisit before enabling. | — | — | — |
| Photos, audio, contacts, calendar, files | **No** | — | — | — |

**Is data processed ephemerally?** OTP SMS text and NPC-chat prompts sent to the AI provider are processed for the request only. The paid tier of the AI provider does not train on them.
