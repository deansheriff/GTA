/**
 * Placeholder "painted" art generator.
 *
 * Real art will be hand-painted (proposal §4). Until then we draw stand-ins at runtime so the
 * M0 style test runs with zero art downloads. Everything here is deterministic (seeded) so the
 * same tile always looks the same.
 */

export type Ctx = CanvasRenderingContext2D;

/** Small seeded RNG (mulberry32). */
export function rng(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function makeCanvas(w: number, h: number): { c: HTMLCanvasElement; g: Ctx } {
  const c = document.createElement('canvas');
  c.width = Math.max(1, Math.round(w));
  c.height = Math.max(1, Math.round(h));
  const g = c.getContext('2d')!;
  return { c, g };
}

/** Shift a hex colour lighter (+) or darker (-) by amount in [-1, 1]. */
export function shade(hex: string, amt: number): string {
  const n = parseInt(hex.slice(1), 16);
  let r = (n >> 16) & 255, gg = (n >> 8) & 255, b = n & 255;
  const t = amt < 0 ? 0 : 255;
  const p = Math.abs(amt);
  r = Math.round((t - r) * p + r);
  gg = Math.round((t - gg) * p + gg);
  b = Math.round((t - b) * p + b);
  return `rgb(${r},${gg},${b})`;
}

/**
 * Fill the current path with a base colour, then dab soft strokes of nearby tones inside it.
 * This is what gives the "painted" texture rather than flat vector fills.
 */
export function paintPath(g: Ctx, path: Path2D, base: string, seed: number, opts: { dabs?: number; spread?: number; size?: number; volume?: boolean; bounds: [number, number, number, number] }) {
  const r = rng(seed);
  const [x0, y0, w, h] = opts.bounds;
  const dabs = opts.dabs ?? Math.round((w * h) / 90);
  const spread = opts.spread ?? 0.12;
  const size = opts.size ?? Math.max(2, Math.min(w, h) / 9);
  g.save();
  g.fillStyle = base;
  g.fill(path);
  g.clip(path);
  for (let i = 0; i < dabs; i++) {
    const x = x0 + r() * w;
    const y = y0 + r() * h;
    const s = size * (0.4 + r());
    g.globalAlpha = 0.08 + r() * 0.18;
    g.fillStyle = shade(base, (r() - 0.5) * 2 * spread);
    g.beginPath();
    g.ellipse(x, y, s, s * (0.45 + r() * 0.4), r() * Math.PI, 0, Math.PI * 2);
    g.fill();
  }
  g.globalAlpha = 1;
  if (opts.volume === false) { g.restore(); return; }
  // Soft top-left light, bottom-right shade: the painted volume.
  const grad = g.createLinearGradient(x0, y0, x0 + w, y0 + h);
  grad.addColorStop(0, 'rgba(255,240,200,0.18)');
  grad.addColorStop(1, 'rgba(30,10,40,0.18)');
  g.fillStyle = grad;
  g.fillRect(x0, y0, w, h);
  g.restore();
}

/** A painterly outline: a dark, slightly broken stroke. */
export function inkPath(g: Ctx, path: Path2D, width = 1.5, colour = 'rgba(40,20,30,0.55)') {
  g.save();
  g.strokeStyle = colour;
  g.lineWidth = width;
  g.lineJoin = 'round';
  g.stroke(path);
  g.restore();
}

export function poly(points: Array<[number, number]>): Path2D {
  const p = new Path2D();
  points.forEach(([x, y], i) => (i === 0 ? p.moveTo(x, y) : p.lineTo(x, y)));
  p.closePath();
  return p;
}

export function boundsOf(points: Array<[number, number]>): [number, number, number, number] {
  const xs = points.map((p) => p[0]);
  const ys = points.map((p) => p[1]);
  const x0 = Math.min(...xs), y0 = Math.min(...ys);
  return [x0, y0, Math.max(...xs) - x0, Math.max(...ys) - y0];
}

/** Soft elliptical blob shadow. */
export function blobShadow(g: Ctx, cx: number, cy: number, rx: number, ry: number, alpha = 0.35) {
  g.save();
  const grad = g.createRadialGradient(cx, cy, 0, cx, cy, rx);
  grad.addColorStop(0, `rgba(20,10,30,${alpha})`);
  grad.addColorStop(1, 'rgba(20,10,30,0)');
  g.fillStyle = grad;
  g.scale(1, ry / rx);
  g.beginPath();
  g.arc(cx, cy * (rx / ry), rx, 0, Math.PI * 2);
  g.fill();
  g.restore();
}
