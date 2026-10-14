#!/usr/bin/env node
/**
 * Turns raw generated art (art-src/raw) into game-ready textures in game/art.
 *   node tools/art/process.mjs
 *
 * - textures: made seamless (half-offset cross-fade) and resized.
 * - singles: trimmed to their visible pixels and resized.
 * - sheets: split on a grid; each cell trimmed. Props become separate files; character
 *   sheets become uniform frame strips with a shared feet baseline (+ JSON for Godot).
 * If a "transparent" image came back with a flat backdrop, the backdrop is keyed out from the corners.
 */
import sharp from 'sharp';
import { mkdirSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';

const RAW = 'art-src/raw';
const OUT = 'game/art';

const JOBS = [
  { src: 'tex-ground-dirt', kind: 'texture', out: 'ground/dirt.png', size: 512 },
  { src: 'tex-ground-island-grass', kind: 'texture', out: 'ground/grass.png', size: 512 },
  { src: 'tex-ground-sand', kind: 'texture', out: 'ground/sand.png', size: 512 },
  { src: 'bld-beach-bar', kind: 'single', out: 'buildings/beach-bar.png', width: 520 },
  { src: 'bld-fisher-hut', kind: 'single', out: 'buildings/fisher-hut.png', width: 380 },
  { src: 'bld-island-cottage', kind: 'single', out: 'buildings/island-cottage.png', width: 400 },
  { src: 'prop-sheet-island', kind: 'sheet', cols: 3, rows: 2, outs: ['props/canoe.png', 'props/nets.png', 'props/beach-umbrella.png', 'props/coconut-cart.png', 'props/palm-cluster.png', 'props/fish-baskets.png'], widths: [300, 200, 220, 170, 300, 150] },
  { src: 'tex-ground-asphalt', kind: 'texture', out: 'ground/asphalt.png', size: 512 },
  { src: 'tex-ground-interlock', kind: 'texture', out: 'ground/interlock.png', size: 512 },
  { src: 'bld-canteen', kind: 'single', out: 'buildings/canteen.png', width: 420 },
  { src: 'bld-pos-shop', kind: 'single', out: 'buildings/pos-shop.png', width: 360 },
  { src: 'bld-bungalow', kind: 'single', out: 'buildings/bungalow.png', width: 520 },
  { src: 'bld-two-storey', kind: 'single', out: 'buildings/two-storey.png', width: 520 },
  { src: 'bld-provision-store', kind: 'single', out: 'buildings/provision-store.png', width: 380 },
  { src: 'prop-sheet-street', kind: 'sheet', cols: 3, rows: 2, outs: ['props/umbrella.png', 'props/generator.png', 'props/kiosk.png', 'props/tyres.png', 'props/drum-chairs.png', 'props/orange-tray.png'], widths: [150, 70, 170, 70, 90, 80] },
  { src: 'prop-sheet-trees', kind: 'sheet', cols: 3, rows: 1, outs: ['props/mango.png', 'props/palm.png', 'props/pole.png'], widths: [230, 190, 90] },
  { src: 'veh-danfo-topdown', kind: 'single', out: 'vehicles/danfo.png', width: 220 },
  { src: 'veh-car-topdown', kind: 'single', out: 'vehicles/car.png', width: 180 },
  { src: 'veh-keke-topdown', kind: 'single', out: 'vehicles/keke.png', width: 120 },
  { src: 'veh-okada-topdown', kind: 'single', out: 'vehicles/okada.png', width: 90 },
  { src: 'chr-tunde-walk-v2', kind: 'frames', cols: 4, rows: 3, out: 'characters/tunde-walk.png', frameH: 96, cut: 70 },
  { src: 'chr-ngozi-walk', kind: 'frames', cols: 4, rows: 3, out: 'characters/ngozi-walk.png', frameH: 96, cut: 110 },
  { src: 'chr-kc-walk', kind: 'frames', cols: 4, rows: 3, out: 'characters/kc-walk.png', frameH: 96, cut: 70 },
  { src: 'chr-story-cast', kind: 'frames', cols: 4, rows: 2, out: 'characters/story-cast.png', frameH: 100, cut: 70 },
  ...['tunde', 'ngozi', 'kc', 'chief', 'pepper', 'salt', 'sule', 'mc', 'ledger', 'bayo', 'mama-chief', 'passenger', 'warden', 'debtor', 'cousin', 'mama-nkem', 'market-woman', 'barber', 'usher', 'kiosk', 'mechanic', 'guest-b', 'guest-c', 'gele-queen', 'teacher', 'pastor', 'visa-officer', 'receipts', 'rival', 'attendant'].map((k) => ({ src: 'pt-' + k, kind: 'single', out: `portraits/${k}.png`, width: 384, cut: 40 })),
  ...['panel-owambe', 'panel-blackout', 'panel-bag', 'panel-family-meeting', 'panel-title', 'panel-generator-wars', 'panel-japa', 'panel-aso-ebi', 'panel-fuel-queue', 'panel-old-notes', 'panel-rally', 'panel-up-nepa', 'panel-ending-a', 'panel-ending-b', 'panel-ending-c', 'panel-ending-d'].map((k) => ({ src: k, kind: 'panel', out: `story/${k}.jpg`, width: 1280 })),
  { src: 'int-owambe-hall', kind: 'panel', out: 'interiors/owambe-hall.jpg', width: 1536 },
  { src: 'int-compound-party', kind: 'panel', out: 'interiors/compound-party.jpg', width: 1536 },
  { src: 'int-stadium', kind: 'panel', out: 'interiors/stadium.jpg', width: 1536 },
  { src: 'chr-pedestrians-a', kind: 'frames', cols: 4, rows: 2, out: 'characters/pedestrians-a.png', frameH: 96 },
  { src: 'chr-pedestrians-b', kind: 'frames', cols: 4, rows: 2, out: 'characters/pedestrians-b.png', frameH: 96 },
];

async function load(name) {
  const file = join(RAW, name + '.png');
  if (!existsSync(file)) return null;
  const { data, info } = await sharp(file).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  return { data, w: info.width, h: info.height };
}

/** If the corners are opaque and similar, treat that colour as backdrop and key it out (flood from edges). */
function keyBackdrop(img) {
  const { data, w, h } = img;
  const px = (x, y) => (y * w + x) * 4;
  const corners = [px(0, 0), px(w - 1, 0), px(0, h - 1), px(w - 1, h - 1)];
  if (corners.every((i) => data[i + 3] < 20)) return img; // already transparent
  const [r0, g0, b0] = [data[corners[0]], data[corners[0] + 1], data[corners[0] + 2]];
  const near = (i) => Math.abs(data[i] - r0) + Math.abs(data[i + 1] - g0) + Math.abs(data[i + 2] - b0) < 48;
  const seen = new Uint8Array(w * h);
  const stack = [];
  for (let x = 0; x < w; x++) stack.push([x, 0], [x, h - 1]);
  for (let y = 0; y < h; y++) stack.push([0, y], [w - 1, y]);
  while (stack.length) {
    const [x, y] = stack.pop();
    if (x < 0 || y < 0 || x >= w || y >= h || seen[y * w + x]) continue;
    seen[y * w + x] = 1;
    const i = px(x, y);
    if (!near(i)) continue;
    data[i + 3] = 0;
    stack.push([x + 1, y], [x - 1, y], [x, y + 1], [x, y - 1]);
  }
  return img;
}

/** Bounding box of pixels with alpha above a threshold inside a region. */
function alphaBounds(img, rx = 0, ry = 0, rw = img.w, rh = img.h, threshold = 16) {
  let x0 = Infinity, y0 = Infinity, x1 = -1, y1 = -1;
  for (let y = ry; y < ry + rh; y++) {
    for (let x = rx; x < rx + rw; x++) {
      if (img.data[(y * img.w + x) * 4 + 3] > threshold) {
        if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y;
      }
    }
  }
  return x1 < 0 ? null : { x: x0, y: y0, w: x1 - x0 + 1, h: y1 - y0 + 1 };
}

/**
 * Largest connected opaque shape inside a cell: returns its bounds and an RGBA buffer
 * containing only that shape (neighbours' stray leaves/fronds are dropped).
 */
function largestComponent(img, rx, ry, rw, rh, threshold = 16) {
  const seen = new Uint8Array(rw * rh);
  let best = null;
  const alpha = (x, y) => img.data[((ry + y) * img.w + (rx + x)) * 4 + 3];
  for (let y0 = 0; y0 < rh; y0++) {
    for (let x0 = 0; x0 < rw; x0++) {
      if (seen[y0 * rw + x0] || alpha(x0, y0) <= threshold) continue;
      const pixels = [];
      const stack = [[x0, y0]];
      seen[y0 * rw + x0] = 1;
      while (stack.length) {
        const [x, y] = stack.pop();
        pixels.push(y * rw + x);
        for (const [nx, ny] of [[x + 1, y], [x - 1, y], [x, y + 1], [x, y - 1]]) {
          if (nx < 0 || ny < 0 || nx >= rw || ny >= rh || seen[ny * rw + nx] || alpha(nx, ny) <= threshold) continue;
          seen[ny * rw + nx] = 1;
          stack.push([nx, ny]);
        }
      }
      if (!best || pixels.length > best.length) best = pixels;
    }
  }
  if (!best) return null;
  let x0 = Infinity, y0 = Infinity, x1 = -1, y1 = -1;
  for (const i of best) { const x = i % rw, y = (i / rw) | 0; if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
  const w = x1 - x0 + 1, h = y1 - y0 + 1;
  const buf = Buffer.alloc(w * h * 4);
  // Include semi-transparent edge pixels next to the shape so anti-aliasing survives.
  const keep = new Uint8Array(rw * rh);
  for (const i of best) keep[i] = 1;
  for (let y = y0; y <= y1; y++) {
    for (let x = x0; x <= x1; x++) {
      let ok = keep[y * rw + x];
      if (!ok) for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) { const nx = x + dx, ny = y + dy; if (nx >= 0 && ny >= 0 && nx < rw && ny < rh && keep[ny * rw + nx]) { ok = 1; break; } }
      if (!ok) continue;
      const s = ((ry + y) * img.w + (rx + x)) * 4, d = ((y - y0) * w + (x - x0)) * 4;
      img.data.copy(buf, d, s, s + 4);
    }
  }
  return { w, h, buf };
}

const toSharp = (img) => sharp(img.data, { raw: { width: img.w, height: img.h, channels: 4 } });

async function save(pipeline, out) {
  const file = join(OUT, out);
  mkdirSync(dirname(file), { recursive: true });
  await pipeline.png({ compressionLevel: 9, palette: false }).toFile(file);
  return file;
}

/** Seamless tile: blend the image with its half-offset copy, weighting the copy near the edges. */
async function seamless(img, size) {
  const { data, w, h } = img;
  const out = Buffer.alloc(data.length);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 4;
      const j = (((y + h / 2) % h) * w + ((x + w / 2) % w)) * 4;
      const edge = Math.min(x, w - 1 - x, y, h - 1 - y) / (w * 0.22);
      const m = Math.min(1, edge) ** 1.5; // 1 = original, 0 = shifted
      for (let c = 0; c < 3; c++) out[i + c] = Math.round(data[i + c] * m + data[j + c] * (1 - m));
      out[i + 3] = 255;
    }
  }
  return sharp(out, { raw: { width: w, height: h, channels: 4 } }).resize(size, size);
}

const report = [];
for (const job of JOBS) {
  const img0 = await load(job.src);
  if (!img0) { report.push(`- ${job.src}: missing (not generated yet)`); continue; }
  if (job.kind === 'texture') {
    report.push(`- ${await save(await seamless(img0, job.size), job.out)}`);
    continue;
  }
  if (job.kind === 'panel') {
    const file = join(OUT, job.out);
    mkdirSync(dirname(file), { recursive: true });
    await toSharp(img0).resize({ width: job.width }).flatten({ background: '#1d1611' }).jpeg({ quality: 84 }).toFile(file);
    report.push(`- ${file}`);
    continue;
  }
  const img = keyBackdrop(img0);
  if (job.cut) {
    // Drop the soft glow/shadow halo some generations paint around figures.
    for (let i = 3; i < img.data.length; i += 4) if (img.data[i] < job.cut) img.data[i] = 0;
  }
  if (job.kind === 'single') {
    const b = alphaBounds(img);
    if (!b) { report.push(`- ${job.src}: empty`); continue; }
    const p = toSharp(img).extract({ left: b.x, top: b.y, width: b.w, height: b.h }).resize({ width: job.width });
    report.push(`- ${await save(p, job.out)} (${b.w}x${b.h} trimmed)`);
    continue;
  }
  const cw = Math.floor(img.w / job.cols), ch = Math.floor(img.h / job.rows);
  if (job.kind === 'sheet') {
    for (let r = 0; r < job.rows; r++) {
      for (let c = 0; c < job.cols; c++) {
        const k = r * job.cols + c;
        if (!job.outs[k]) continue;
        const comp = largestComponent(img, c * cw, r * ch, cw, ch);
        if (!comp) { report.push(`- ${job.outs[k]}: empty cell`); continue; }
        const p = sharp(comp.buf, { raw: { width: comp.w, height: comp.h, channels: 4 } }).resize({ width: job.widths[k] });
        report.push(`- ${await save(p, job.outs[k])}`);
      }
    }
    continue;
  }
  if (job.kind === 'frames') {
    // Uniform frames: scale every cell by the same factor so characters keep their size,
    // and align feet (bottom of the alpha box) to a shared baseline.
    const boxes = [];
    for (let r = 0; r < job.rows; r++) for (let c = 0; c < job.cols; c++) boxes.push(alphaBounds(img, c * cw, r * ch, cw, ch));
    const maxH = Math.max(...boxes.filter(Boolean).map((b) => b.h));
    const maxW = Math.max(...boxes.filter(Boolean).map((b) => b.w));
    const scale = job.frameH / maxH;
    const fw = Math.ceil(maxW * scale) + 4, fh = job.frameH + 4;
    const composites = [];
    for (let k = 0; k < boxes.length; k++) {
      const b = boxes[k];
      if (!b) continue;
      const tw = Math.max(1, Math.round(b.w * scale)), th = Math.max(1, Math.round(b.h * scale));
      const buf = await toSharp(img).extract({ left: b.x, top: b.y, width: b.w, height: b.h }).resize(tw, th).png().toBuffer();
      const col = k % job.cols, row = Math.floor(k / job.cols);
      composites.push({ input: buf, left: col * fw + Math.round((fw - tw) / 2), top: row * fh + (fh - 2 - th) });
    }
    const sheet = sharp({ create: { width: fw * job.cols, height: fh * job.rows, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } }).composite(composites);
    const file = await save(sheet, job.out);
    writeFileSync(file.replace(/\.png$/, '.json'), JSON.stringify({ frameW: fw, frameH: fh, cols: job.cols, rows: job.rows, baseline: fh - 2 }, null, 2) + '\n');
    report.push(`- ${file} (${job.cols}x${job.rows} frames of ${fw}x${fh})`);
  }
}
console.log(report.join('\n'));
