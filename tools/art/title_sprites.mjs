#!/usr/bin/env node
/**
 * Cuts the title-screen street sprites (spec-title.json) into single trimmed PNGs for
 * game/art/title/. The generator leaves a faint glow haze in the alpha channel, so weak
 * alpha is dropped. The keke's front emblem is painted out (no brand-like badges).
 *
 *   node tools/art/title_sprites.mjs [--stats]
 */
import sharp from 'sharp';
import { mkdirSync } from 'node:fs';

const OUT = 'game/art/title';
const SHEETS = [
  { file: 'art-src/raw/title-walkers.png', cols: 4, rows: 2, names: ['walk-f-orange', 'walk-f-jersey', 'walk-f-agbada', 'walk-f-school', 'walk-b-bread', 'walk-b-sack', 'walk-b-gown', 'walk-b-boy'] },
  { file: 'art-src/raw/title-vehicles.png', cols: 2, rows: 2, names: ['okada-f', 'okada-b', 'keke-f', 'keke-b'], cut: 215, erode: 2 },
];
const ALPHA_CUT = 150; // below this the pixel is haze, not painting
const MAX_H = 360;

mkdirSync(OUT, { recursive: true });
for (const s of SHEETS) {
  const { data, info } = await sharp(s.file).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  if (process.argv.includes('--stats')) {
    const hist = new Array(11).fill(0);
    for (let i = 3; i < data.length; i += 4) hist[Math.floor(data[i] / 25.5)]++;
    console.log(s.file, hist.map((h) => ((h / (info.width * info.height)) * 100).toFixed(1)).join(' '));
  }
  const cut = s.cut ?? ALPHA_CUT;
  for (let i = 3; i < data.length; i += 4) {
    const a = data[i];
    data[i] = a < cut ? 0 : Math.min(255, Math.round(((a - cut) / (255 - cut)) * 255 * 1.6));
  }
  // The vehicle sheet's haze is light grey: shave its edge pixels off.
  for (let pass = 0; pass < (s.erode ?? 0); pass++) {
    const alpha = new Uint8Array(info.width * info.height);
    for (let i = 0; i < alpha.length; i++) alpha[i] = data[i * 4 + 3];
    for (let y = 1; y < info.height - 1; y++) {
      for (let x = 1; x < info.width - 1; x++) {
        const i = y * info.width + x;
        data[i * 4 + 3] = Math.min(alpha[i], alpha[i - 1], alpha[i + 1], alpha[i - info.width], alpha[i + info.width]);
      }
    }
  }
  const cw = Math.floor(info.width / s.cols);
  const ch = Math.floor(info.height / s.rows);
  for (let k = 0; k < s.names.length; k++) {
    const cx = (k % s.cols) * cw;
    const cy = Math.floor(k / s.cols) * ch;
    const cell = Buffer.alloc(cw * ch * 4);
    for (let y = 0; y < ch; y++) data.copy(cell, y * cw * 4, ((cy + y) * info.width + cx) * 4, ((cy + y) * info.width + cx + cw) * 4);
    const img = sharp(cell, { raw: { width: cw, height: ch, channels: 4 } }).trim({ threshold: 1 });
    const buf = await img.png().toBuffer();
    const meta = await sharp(buf).metadata();
    const scale = Math.min(1, MAX_H / (meta.height ?? MAX_H));
    const w = Math.round((meta.width ?? 1) * scale);
    const h = Math.round((meta.height ?? 1) * scale);
    const out = await sharp(buf).resize(w, h).raw().toBuffer();
    if (s.names[k] === 'keke-f') paintOutEmblem(out, w);
    await sharp(out, { raw: { width: w, height: h, channels: 4 } }).png({ compressionLevel: 9 }).toFile(`${OUT}/${s.names[k]}.png`);
    console.log(`${OUT}/${s.names[k]}.png`);
  }
}

/** The grille badge on the keke front (output coords ~x 72-106, y 174-204): fill with the grille's dark paint. */
function paintOutEmblem(px, w) {
  const at = (x, y) => (y * w + x) * 4;
  const o0 = at(68, 196);
  const [r, g, b] = [px[o0], px[o0 + 1], px[o0 + 2]];
  for (let y = 172; y < 206; y++) {
    for (let x = 70; x < 108; x++) {
      const o = at(x, y);
      const n = ((x * 7 + y * 13) % 9) - 4; // a little painterly grain
      px[o] = Math.max(0, r + n); px[o + 1] = Math.max(0, g + n); px[o + 2] = Math.max(0, b + n);
    }
  }
}
