#!/usr/bin/env node
/** Hue histogram of a sprite sheet's saturated pixels (to tune the outfit recolour shader). */
import sharp from 'sharp';
for (const f of process.argv.slice(2)) {
  const { data, info } = await sharp(f).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const bins = new Array(36).fill(0);
  let total = 0;
  for (let i = 0; i < data.length; i += 4) {
    if (data[i + 3] < 200) continue;
    const r = data[i] / 255, g = data[i + 1] / 255, b = data[i + 2] / 255;
    const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn;
    if (mx < 0.15 || d / mx < 0.5) continue;
    let h = mx === r ? ((g - b) / d) % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
    h = (h * 60 + 360) % 360;
    bins[Math.floor(h / 10)]++; total++;
  }
  console.log(f, total, bins.map((b, i) => (b / total > 0.03 ? `${i * 10}:${Math.round((b / total) * 100)}%` : '')).filter(Boolean).join(' '));
}
