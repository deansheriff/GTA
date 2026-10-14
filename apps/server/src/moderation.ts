import type { Db } from './db.ts';

/**
 * Pre-send text moderation (proposal §7). Fast rules on every message; anything blocked is never
 * shown. Borderline content can be held for a moderator ("hold"). Gemini review of held items is
 * an M6 add-on; people decide.
 *
 * Rules:
 *  - personal data: phone numbers, bank account numbers, emails
 *  - off-platform payment / scams: "send to my opay", account numbers, crypto, "real money"
 *  - links (only verified players may post them)
 *  - a small slur/abuse list (extend via MOD_EXTRA_WORDS, comma-separated, from the moderators)
 */
export type Verdict = { ok: true; text: string } | { ok: false; reason: string; hold?: boolean };

const ABUSE = ['mumu', 'ode', 'olodo', 'idiot', 'stupid', 'fool', 'bastard', 'ashawo', 'werey', 'shege', 'fuck', 'shit', 'bitch'];
const HATE = ['nyamiri', 'aboki', 'ofemanu', 'hausa goat', 'yoruba demon', 'igbo thief'];
const SCAM = [/\b(opay|palmpay|kuda|moniepoint)\b/i, /\bsend (me )?(real )?money\b/i, /\b(btc|usdt|bitcoin|crypto|forex)\b/i, /\bsell(ing)? (game )?money\b/i, /\baccount (no|number)\b/i, /\bwhatsapp me\b/i];
const PHONE = /(\+?234|0)[789][01]\d{8}\b|\b\d{11}\b/;
const ACCOUNT = /\b\d{10}\b/;
const EMAIL = /[\w.+-]+@[\w-]+\.[\w.]+/;
const LINK = /(https?:\/\/|www\.|\b[\w-]+\.(com|ng|net|org|io|xyz|link|me)\b)/i;

function words(): string[] {
  const extra = (process.env.MOD_EXTRA_WORDS ?? '').split(',').map((w) => w.trim().toLowerCase()).filter(Boolean);
  return [...ABUSE, ...extra];
}

export function checkText(raw: unknown, opts: { verified?: boolean; max?: number } = {}): Verdict {
  if (typeof raw !== 'string') return { ok: false, reason: 'empty' };
  // Normalise: strip control chars, collapse whitespace, cap length.
  const text = raw.replace(/[\u0000-\u001f\u007f​-‏‪-‮]/g, '').replace(/\s+/g, ' ').trim();
  if (!text) return { ok: false, reason: 'empty' };
  if (text.length > (opts.max ?? 280)) return { ok: false, reason: 'too_long' };
  const lower = text.toLowerCase();
  // Leetspeak-ish folding so "f*ck" and "fvck" don't slip through trivially.
  const folded = lower.replace(/[*@4]/g, 'a').replace(/[1!|]/g, 'i').replace(/0/g, 'o').replace(/3/g, 'e').replace(/\$|5/g, 's').replace(/v/g, 'u');
  for (const h of HATE) if (lower.includes(h) || folded.includes(h)) return { ok: false, reason: 'hate' };
  if (PHONE.test(text) || EMAIL.test(text)) return { ok: false, reason: 'personal_data' };
  for (const s of SCAM) if (s.test(text)) return { ok: false, reason: 'off_platform_payment' };
  if (ACCOUNT.test(text)) return { ok: false, reason: 'off_platform_payment' };
  if (LINK.test(text) && !opts.verified) return { ok: false, reason: 'links_need_verification' };
  for (const w of words()) {
    const re = new RegExp(`\\b${w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'i');
    if (re.test(lower) || re.test(folded.replace(/u/g, 'u'))) return { ok: false, reason: 'abuse' };
  }
  // Shouting walls of caps are held, not blocked: a moderator decides.
  if (text.length > 40 && text === text.toUpperCase() && /[A-Z]/.test(text)) return { ok: false, reason: 'shouting', hold: true };
  return { ok: true, text };
}

/** Strike ladder: warning → 24-hour mute → 7-day ban → permanent ban (proposal §7). */
export async function addStrike(db: Db, playerId: string, reason: string, by: string): Promise<string> {
  const r = await db.query<{ strikes: number }>('UPDATE players SET strikes = strikes + 1 WHERE id = $1 RETURNING strikes', [playerId]);
  const n = Number(r.rows[0]?.strikes ?? 0);
  let action = 'warning';
  if (n === 2) {
    action = 'mute_24h';
    await db.query(`UPDATE players SET muted_until = now() + interval '24 hours' WHERE id = $1`, [playerId]);
  } else if (n === 3) {
    action = 'ban_7d';
    await db.query(`UPDATE players SET banned_until = now() + interval '7 days' WHERE id = $1`, [playerId]);
  } else if (n >= 4) {
    action = 'ban_permanent';
    await db.query(`UPDATE players SET banned_until = 'infinity' WHERE id = $1`, [playerId]);
  }
  await db.query('INSERT INTO strikes_log (player_id, reason, action, by_actor) VALUES ($1, $2, $3, $4)', [playerId, reason, action, by]);
  return action;
}
