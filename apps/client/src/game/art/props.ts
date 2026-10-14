import { PAL } from './palette';
import { blobShadow, boundsOf, inkPath, makeCanvas, paintPath, poly, rng, shade } from './paint';

/** Every prop canvas is drawn with its ground contact point at (w/2, h - pad). */
export interface PropArt {
  canvas: HTMLCanvasElement;
  originX: number;
  originY: number;
}

const done = (c: HTMLCanvasElement, groundY: number): PropArt => ({ canvas: c, originX: 0.5, originY: groundY / c.height });

/** A big kerbside umbrella: the POS / recharge-card stand. */
export function drawUmbrella(colours: [string, string], label: string | null, s: number, seed: number): PropArt {
  const w = 110 * s, h = 120 * s;
  const { c, g } = makeCanvas(w, h);
  const cx = w / 2, gy = h - 8 * s;
  blobShadow(g, cx + 6 * s, gy, 46 * s, 14 * s, 0.3);
  // Table with a POS machine.
  const table: Array<[number, number]> = [[cx - 22 * s, gy - 30 * s], [cx + 22 * s, gy - 30 * s], [cx + 22 * s, gy - 4 * s], [cx - 22 * s, gy - 4 * s]];
  paintPath(g, poly(table), '#7a5536', seed, { bounds: boundsOf(table), dabs: 15 });
  g.fillStyle = '#222'; g.fillRect(cx - 6 * s, gy - 38 * s, 12 * s, 8 * s);
  g.fillStyle = '#7fd4ff'; g.fillRect(cx - 4 * s, gy - 37 * s, 8 * s, 4 * s);
  // Pole.
  g.fillStyle = '#ddd'; g.fillRect(cx - 1.5 * s, gy - 92 * s, 3 * s, 70 * s);
  // Canopy: alternating panels.
  const top = gy - 100 * s;
  for (let i = 0; i < 8; i++) {
    const a0 = Math.PI + (i / 8) * Math.PI, a1 = Math.PI + ((i + 1) / 8) * Math.PI;
    const pts: Array<[number, number]> = [
      [cx, top - 6 * s],
      [cx + Math.cos(a0) * 52 * s, top + 22 * s + Math.sin(a0) * -8 * s],
      [cx + Math.cos(a1) * 52 * s, top + 22 * s + Math.sin(a1) * -8 * s],
    ];
    paintPath(g, poly(pts), colours[i % 2]!, seed + i, { bounds: boundsOf(pts), dabs: 10 });
    inkPath(g, poly(pts), 1 * s);
  }
  if (label) {
    g.fillStyle = '#fff6e0';
    g.font = `bold ${9 * s}px system-ui, sans-serif`;
    g.textAlign = 'center';
    g.fillText(label, cx, top + 26 * s);
  }
  return done(c, gy);
}

/** Electric pole with a transformer box: lit/unlit state is drawn by the lighting overlay. */
export function drawPole(s: number, withTransformer: boolean, seed: number): PropArt {
  const w = 60 * s, h = 190 * s;
  const { c, g } = makeCanvas(w, h);
  const cx = w / 2, gy = h - 6 * s;
  blobShadow(g, cx + 4 * s, gy, 12 * s, 4 * s, 0.35);
  const pole: Array<[number, number]> = [[cx - 3 * s, gy], [cx + 3 * s, gy], [cx + 2 * s, gy - 175 * s], [cx - 2 * s, gy - 175 * s]];
  paintPath(g, poly(pole), '#6b4a30', seed, { bounds: boundsOf(pole), dabs: 20 });
  g.fillStyle = '#4a3322'; g.fillRect(cx - 22 * s, gy - 165 * s, 44 * s, 4 * s);
  for (const dx of [-18, 0, 18]) { g.fillStyle = '#d6e6f0'; g.fillRect(cx + (dx - 1.5) * s, gy - 170 * s, 3 * s, 5 * s); }
  if (withTransformer) {
    const box: Array<[number, number]> = [[cx - 14 * s, gy - 120 * s], [cx + 14 * s, gy - 120 * s], [cx + 14 * s, gy - 90 * s], [cx - 14 * s, gy - 90 * s]];
    paintPath(g, poly(box), '#7d8a8f', seed + 1, { bounds: boundsOf(box), dabs: 12 });
    inkPath(g, poly(box), 1 * s);
    g.fillStyle = '#b33'; g.font = `bold ${7 * s}px sans-serif`; g.textAlign = 'center';
    g.fillText('ELDDC', cx, gy - 102 * s);
  }
  return done(c, gy);
}

/** Small "I-pass-my-neighbour" petrol generator. */
export function drawGenerator(s: number, seed: number): PropArt {
  const w = 54 * s, h = 46 * s;
  const { c, g } = makeCanvas(w, h);
  const cx = w / 2, gy = h - 4 * s;
  blobShadow(g, cx, gy, 22 * s, 6 * s, 0.4);
  const front: Array<[number, number]> = [[cx - 18 * s, gy - 4 * s], [cx + 10 * s, gy], [cx + 10 * s, gy - 22 * s], [cx - 18 * s, gy - 26 * s]];
  const side: Array<[number, number]> = [[cx + 10 * s, gy], [cx + 20 * s, gy - 6 * s], [cx + 20 * s, gy - 28 * s], [cx + 10 * s, gy - 22 * s]];
  const top: Array<[number, number]> = [[cx - 18 * s, gy - 26 * s], [cx + 10 * s, gy - 22 * s], [cx + 20 * s, gy - 28 * s], [cx - 8 * s, gy - 32 * s]];
  paintPath(g, poly(front), '#c0392b', seed, { bounds: boundsOf(front), dabs: 14 });
  paintPath(g, poly(side), shade('#c0392b', -0.25), seed + 1, { bounds: boundsOf(side), dabs: 8 });
  paintPath(g, poly(top), '#f1c40f', seed + 2, { bounds: boundsOf(top), dabs: 8 });
  [front, side, top].forEach((p) => inkPath(g, poly(p), 1 * s));
  g.fillStyle = '#333'; g.fillRect(cx - 12 * s, gy - 18 * s, 8 * s, 8 * s); // panel
  return done(c, gy);
}

export function drawPalm(s: number, seed: number): PropArt {
  const w = 120 * s, h = 170 * s;
  const { c, g } = makeCanvas(w, h);
  const r = rng(seed);
  const cx = w / 2, gy = h - 6 * s;
  blobShadow(g, cx + 10 * s, gy, 34 * s, 10 * s, 0.3);
  g.strokeStyle = '#7a5a3a'; g.lineWidth = 7 * s; g.lineCap = 'round';
  g.beginPath(); g.moveTo(cx, gy); g.quadraticCurveTo(cx + 12 * s, gy - 70 * s, cx + 4 * s, gy - 130 * s); g.stroke();
  const tx = cx + 4 * s, ty = gy - 130 * s;
  for (let i = 0; i < 9; i++) {
    const ang = (i / 9) * Math.PI * 2 + r() * 0.3;
    const len = (40 + r() * 16) * s;
    const ex = tx + Math.cos(ang) * len, ey = ty + Math.sin(ang) * len * 0.55 + 12 * s;
    const leaf: Array<[number, number]> = [[tx, ty], [(tx + ex) / 2 + Math.sin(ang) * 8 * s, (ty + ey) / 2 - 10 * s], [ex, ey], [(tx + ex) / 2 - Math.sin(ang) * 6 * s, (ty + ey) / 2]];
    paintPath(g, poly(leaf), i % 2 ? PAL.grass : PAL.grassDark, seed + i, { bounds: boundsOf(leaf), dabs: 10, spread: 0.25 });
  }
  return done(c, gy);
}
