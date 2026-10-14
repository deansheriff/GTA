import { PAL } from './palette';
import { blobShadow, makeCanvas, rng, shade, type Ctx } from './paint';

/**
 * Chunky placeholder people in The Omins' proportions: big head, big hands, short legs.
 * Real heroes will be painted Spine rigs (proposal §4.2); this draws a 4-direction,
 * 4-frame walk sheet so movement, depth and scale can be tested now.
 */
export interface Look {
  skin: string;
  top: string;
  bottom: string;
  hair: 'low' | 'afro' | 'gele' | 'cap' | 'braids';
  hairColour: string;
  extra?: 'towel' | 'ringlight' | 'wrapper' | 'none';
  build: 'slim' | 'solid';
}

export const TUNDE: Look = { skin: '#5a3825', top: '#c0392b', bottom: '#2c3e50', hair: 'low', hairColour: '#111', extra: 'towel', build: 'slim' };
export const AUNTY_BOSS: Look = { skin: '#6e4430', top: '#e67e22', bottom: '#e67e22', hair: 'gele', hairColour: '#16a085', extra: 'wrapper', build: 'solid' };
export const KC: Look = { skin: '#7d4f36', top: '#8e44ad', bottom: '#1b2631', hair: 'afro', hairColour: '#1a1a1a', extra: 'ringlight', build: 'slim' };

export function randomLook(seed: number): Look {
  const r = rng(seed);
  const pick = <T,>(xs: readonly T[]) => xs[Math.floor(r() * xs.length)]!;
  const hair = pick(['low', 'afro', 'gele', 'cap', 'braids'] as const);
  const top = r() < 0.3 ? pick(PAL.ankara) : pick(PAL.shirts);
  return {
    skin: pick(PAL.skin),
    top,
    bottom: hair === 'gele' && r() < 0.6 ? top : pick(PAL.trousers),
    hair,
    hairColour: hair === 'gele' || hair === 'cap' ? pick(PAL.ankara) : '#151010',
    extra: hair === 'gele' ? 'wrapper' : 'none',
    build: r() < 0.5 ? 'slim' : 'solid',
  };
}

export const FRAME_W = 48;
export const FRAME_H = 76;
export const CHAR_DIRS = ['s', 'e', 'n', 'w'] as const;
export const WALK_FRAMES = 4;

/** Sprite sheet: rows = directions (s, e, n, w), columns = walk frames. */
export function drawCharacterSheet(look: Look, s: number): HTMLCanvasElement {
  const fw = FRAME_W * s, fh = FRAME_H * s;
  const { c, g } = makeCanvas(fw * WALK_FRAMES, fh * CHAR_DIRS.length);
  CHAR_DIRS.forEach((dir, row) => {
    for (let f = 0; f < WALK_FRAMES; f++) {
      g.save();
      g.translate(f * fw, row * fh);
      if (dir === 'w') { g.translate(fw, 0); g.scale(-1, 1); }
      drawFrame(g, look, dir === 'w' ? 'e' : dir, f, s);
      g.restore();
    }
  });
  return c;
}

function drawFrame(g: Ctx, look: Look, dir: 's' | 'e' | 'n', frame: number, s: number) {
  const cx = (FRAME_W / 2) * s;
  const gy = (FRAME_H - 4) * s;
  const swing = [0, 1, 0, -1][frame]!;
  const bob = frame % 2 === 0 ? 0 : -1.5 * s;
  const bw = (look.build === 'solid' ? 22 : 17) * s;

  blobShadow(g, cx, gy, 14 * s, 4 * s, 0.35);

  // Legs.
  g.fillStyle = look.bottom;
  const legX = dir === 'e' ? [cx - 3 * s + swing * 4 * s, cx + 1 * s - swing * 4 * s] : [cx - 6 * s, cx + 2 * s];
  const legLift = dir === 'e' ? [0, 0] : [swing > 0 ? -2 * s : 0, swing < 0 ? -2 * s : 0];
  legX.forEach((x, i) => g.fillRect(x, gy - 18 * s + legLift[i]!, 5 * s, 16 * s));
  g.fillStyle = '#2a1d16';
  legX.forEach((x, i) => g.fillRect(x - 1 * s, gy - 3 * s + legLift[i]!, 7 * s, 3 * s));

  // Wrapper / long dress covers the legs for aunties.
  if (look.extra === 'wrapper') {
    g.fillStyle = look.bottom;
    g.beginPath();
    g.moveTo(cx - bw / 2, gy - 34 * s + bob); g.lineTo(cx + bw / 2, gy - 34 * s + bob);
    g.lineTo(cx + bw / 2 + 2 * s, gy - 4 * s); g.lineTo(cx - bw / 2 - 2 * s, gy - 4 * s); g.closePath(); g.fill();
    patternDots(g, cx - bw / 2, gy - 34 * s, bw, 30 * s, shade(look.bottom, 0.35), s);
  }

  // Body.
  const top = gy - 40 * s + bob;
  g.fillStyle = look.top;
  roundRect(g, cx - bw / 2, top, bw, 24 * s, 6 * s);
  g.fill();
  g.fillStyle = shade(look.top, -0.2);
  g.fillRect(cx - bw / 2, top + 18 * s, bw, 6 * s);

  // Arms with big hands.
  const armSwing = dir === 'e' ? swing * 3 * s : swing * 1.5 * s;
  g.fillStyle = look.top;
  if (dir !== 'e') {
    g.fillRect(cx - bw / 2 - 5 * s, top + 3 * s + armSwing, 5 * s, 14 * s);
    g.fillRect(cx + bw / 2, top + 3 * s - armSwing, 5 * s, 14 * s);
    g.fillStyle = look.skin;
    g.beginPath(); g.arc(cx - bw / 2 - 2.5 * s, top + 19 * s + armSwing, 3.5 * s, 0, Math.PI * 2); g.fill();
    g.beginPath(); g.arc(cx + bw / 2 + 2.5 * s, top + 19 * s - armSwing, 3.5 * s, 0, Math.PI * 2); g.fill();
  } else {
    g.fillRect(cx - 2 * s + armSwing, top + 3 * s, 5 * s, 14 * s);
    g.fillStyle = look.skin;
    g.beginPath(); g.arc(cx + 0.5 * s + armSwing, top + 19 * s, 3.5 * s, 0, Math.PI * 2); g.fill();
  }

  // Towel on the shoulder (Tunde) or ring light (KC).
  if (look.extra === 'towel') { g.fillStyle = '#f4f1e8'; g.fillRect(cx + (dir === 'e' ? -4 : bw / 2 - 8) * s, top - 1 * s, 7 * s, 16 * s); }
  if (look.extra === 'ringlight' && dir !== 'n') {
    g.strokeStyle = '#fffbe6'; g.lineWidth = 2.5 * s;
    g.beginPath(); g.arc(cx + bw / 2 + 6 * s, top - 6 * s, 6 * s, 0, Math.PI * 2); g.stroke();
  }

  // Head: big and round.
  const hy = top - 13 * s;
  g.fillStyle = look.skin;
  g.beginPath(); g.arc(cx, hy, 13 * s, 0, Math.PI * 2); g.fill();

  // Hair / headwear.
  g.fillStyle = look.hairColour;
  switch (look.hair) {
    case 'low': g.beginPath(); g.arc(cx, hy - 2 * s, 13 * s, Math.PI * 1.05, Math.PI * 1.95); g.fill(); break;
    case 'afro': g.beginPath(); g.arc(cx, hy - 5 * s, 15 * s, Math.PI * 0.95, Math.PI * 2.05); g.fill(); break;
    case 'braids':
      g.beginPath(); g.arc(cx, hy - 2 * s, 13.5 * s, Math.PI, Math.PI * 2); g.fill();
      for (let i = -2; i <= 2; i++) g.fillRect(cx + i * 4 * s - 1 * s, hy, 2.5 * s, 14 * s);
      break;
    case 'cap': g.fillRect(cx - 13 * s, hy - 12 * s, 26 * s, 8 * s); if (dir !== 'n') g.fillRect(cx - (dir === 'e' ? 0 : 6) * s, hy - 6 * s, 16 * s, 3 * s); break;
    case 'gele':
      g.beginPath();
      g.ellipse(cx, hy - 10 * s, 18 * s, 10 * s, -0.25, 0, Math.PI * 2); g.fill();
      g.fillStyle = shade(look.hairColour, 0.3);
      g.beginPath(); g.ellipse(cx + 8 * s, hy - 16 * s, 8 * s, 5 * s, 0.6, 0, Math.PI * 2); g.fill();
      break;
  }

  // Face.
  if (dir !== 'n') {
    g.fillStyle = '#1a1010';
    const ex = dir === 'e' ? [cx + 5 * s] : [cx - 4.5 * s, cx + 4.5 * s];
    ex.forEach((x) => { g.beginPath(); g.ellipse(x, hy + 1 * s, 1.6 * s, 2.2 * s, 0, 0, Math.PI * 2); g.fill(); });
    g.strokeStyle = 'rgba(40,15,10,0.7)'; g.lineWidth = 1.2 * s;
    g.beginPath(); g.arc(dir === 'e' ? cx + 6 * s : cx, hy + 5 * s, 3 * s, 0.15 * Math.PI, 0.85 * Math.PI); g.stroke();
  }
}

function roundRect(g: Ctx, x: number, y: number, w: number, h: number, r: number) {
  g.beginPath();
  g.moveTo(x + r, y);
  g.arcTo(x + w, y, x + w, y + h, r);
  g.arcTo(x + w, y + h, x, y + h, r);
  g.arcTo(x, y + h, x, y, r);
  g.arcTo(x, y, x + w, y, r);
  g.closePath();
}

function patternDots(g: Ctx, x: number, y: number, w: number, h: number, colour: string, s: number) {
  g.save();
  g.fillStyle = colour;
  for (let yy = y + 3 * s; yy < y + h; yy += 7 * s) {
    for (let xx = x + 3 * s; xx < x + w; xx += 7 * s) {
      g.beginPath(); g.arc(xx, yy, 1.4 * s, 0, Math.PI * 2); g.fill();
    }
  }
  g.restore();
}
