# Deploy the Naija Street Life server on Coolify + Cloudflare

The Android game talks to one server:
- HTTPS API: `/api/*`
- Realtime WebSocket: `/ws`

The server runs as a **Docker Compose** stack with two services:
- `app`: Node.js, Fastify and WebSockets.
- `postgres`: a private PostgreSQL 17 database with a persistent volume.

This matches how you deployed your earlier prototype.

## 1. Coolify application
1. **New resource → Application → Public/Private Git:**
   - Repository: `https://github.com/deansheriff/GTA`
   - Branch: `main`
2. **Build pack:**
   - Choose **Docker Compose**.
   - Base Directory: `/`
   - Compose Location: `/compose.yaml`
   - Use the normal Coolify-managed mode, not Raw.
3. **Environment variables:**
   - `POSTGRES_PASSWORD` *(required)*: a long random value, e.g. from `openssl rand -hex 32`.
     - Enter it raw, without quotes.
     - If it contains `$`, tick *Literal*.
     - Never commit it.
     - After the first deploy, don't change it casually: changing the variable does
       not change the password stored inside an existing database.
   - `GEMINI_API_KEY` *(optional now)*: needed from Milestone 3, when NPC dialogue
     and news run on the server. Stored only in Coolify, never in the APK.
   - `TRUSTED_PROXY_CIDRS` *(optional)*: your Coolify proxy or Cloudflare IP ranges,
     for correct client IPs in rate limits.
   - **Online features (M5).** Without these, the game still runs; phone verification
     and the moderation console stay switched off.
     - `PHONE_PEPPER`: a long random value (`openssl rand -hex 32`). Phone numbers are
       stored only as a keyed hash, and this is the key. **Never change it** after
       launch, or verified players lose their phone link.
     - `SMS_PROVIDER=webhook`, `SMS_WEBHOOK_URL` and `SMS_WEBHOOK_TOKEN` 🔒: the server
       POSTs `{"to": "+234…", "message": "…"}` with `Authorization: Bearer <token>`.
       Point it at your SMS gateway, or at a small relay that calls your provider's
       API. Choosing and paying for an SMS provider is your decision.
     - `ADMIN_TOKEN`: at least 24 random characters. It turns on the moderation
       console at `https://game.YOUR-DOMAIN/admin`. Give it only to moderators, and
       have each one type their name so the audit trail shows who did what.
     - `MOD_EXTRA_WORDS` *(optional)*: extra blocked words, comma-separated, from your
       Pidgin/Yoruba/Igbo/Hausa moderators.
   - **AI and news (M6).** Without these, NPCs use rules and template lines only.
     - `GEMINI_API_KEY`: a paid-tier key. Free tiers may train on prompts, and player
       chat must not go there. The project's prepaid credits must be topped up in
       AI Studio.
     - `AI_DAILY_BUDGET_USD` *(default 2)*: a hard daily cap. When it's reached, NPCs
       fall back to rules until midnight. Spend is shown in the console (AI tab).
     - `GEMINI_MODEL` *(default `gemini-3.1-flash-lite`)*.
     - `NEWS_FEEDS` ⚖️: comma-separated `Outlet|https://…/rss` pairs, for example
       `Punch|https://punchng.com/feed/`. **You choose the outlets.** Check each one's
       terms for headline-and-link use. The game stores only the headline, link and a
       short lede, writes its own neutral summary, and always credits the outlet.
     - Banter lines wait in the console's **News** tab until a moderator approves them.
       *News auto-publish*, *live NPC chat* and every kill switch live in the **AI** tab.
4. **Domains:** select service **app** and enter `https://game.YOUR-DOMAIN:8787`.
   - The `:8787` tells Coolify the container port.
   - Players still use plain `https://game.YOUR-DOMAIN`.
5. **Deploy.** Check the logs, then open `https://game.YOUR-DOMAIN/api/health`.
   It should show `{"ok":true,"db":true}`.

Your Coolify host needs nothing else: no Godot, Java, Android SDK or Node. Docker
builds the server.

## 2. Cloudflare
Add a **separate hostname for the game** (exposing the Coolify dashboard doesn't
expose the game).

- **Cloudflare Tunnel, with `cloudflared` on the host:** publish
  `game.YOUR-DOMAIN` → `http://localhost:80` (Coolify's proxy), keeping the hostname.
- **`cloudflared` in Docker:** `localhost` is the tunnel container itself. Point it
  at the Coolify proxy's address on a shared network instead.
- **WebSockets:** Cloudflare supports them through Tunnels and proxied DNS with no
  extra setting. (The dashboard toggle *Network → WebSockets* must stay **on**; it
  is on by default.)
  - Cloudflare closes idle WebSockets after about 100 s. The server pings every
    30 s, so connections stay open.
- **Caching:** keep `/api/*` and `/ws` out of any *Cache Everything* rule.
- **TLS:** use *Full (strict)* when your origin has a valid certificate.

## 3. Check it from your PC
```bash
node scripts/smoke-ws.mjs https://game.YOUR-DOMAIN
```
It checks health, then connects two test players over `wss://` and confirms they
see each other.

## 4. Point the game at it
- In the game: **Settings → Online → Server address** = `game.YOUR-DOMAIN`.
- Or bake a default into the build: set `naija/online/default_server` in
  `game/project.godot`.
- The phone keeps a private guest token, issued once by the server. It holds no
  secrets of yours: no API keys and no Cloudflare tokens.

## What persists, and backups
- **PostgreSQL** (`nsl_postgres` volume) holds players: id, name, look, a hash of
  the guest token, and timestamps.
- The volume survives redeploys but **is not a backup**.
  - Use Coolify's database backups, or a scheduled `pg_dump`, stored off this server.
  - Test a restore once.
- The `postgres` service has no public port. Keep it that way.

## Scaling notes
- **Room size:** one `app` instance handles the M0/M1 load. A room holds 80
  players; more open `yaba-2`, `yaba-3` automatically.
- **Running several instances** needs shared room state (Redis), planned for when
  player numbers call for it.
- **Data per player:** players only receive nearby players who moved (about 10
  updates a second at most), so standing still costs almost no data.
