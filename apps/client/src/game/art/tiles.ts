import { HALF_H, HALF_W, TILE_H, TILE_W } from './iso';
import { PAL, SIGNS } from './palette';
import { blobShadow, boundsOf, inkPath, makeCanvas, paintPath, poly, rng, shade, type Ctx } from './paint';

export type TileKind = 'earth' | 'grass' | 'road_x' | 'road_y' | 'interlock' | 'gutter_x' | 'gutter_y';

const diamond = (s: number): Array<[number, number]> => [
  [HALF_W * s, 0],
  [TILE_W * s, HALF_H * s],
  [HALF_W * s, TILE_H * s],
  [0, HALF_H * s],
];

/** Map a point in tile-local unit coords (u along +x tile axis, v along +y) to canvas px. */
const uv = (u: number, v: number, s: number): [number, number] => [(HALF_W + (u - v) * HALF_W) * s, (u + v) * HALF_H * s];

export function drawTile(kind: TileKind, variant: number, s: number): HTMLCanvasElement {
  const { c, g } = makeCanvas(TILE_W * s, TILE_H * s);
  const d = diamond(s);
  const p = poly(d);
  const b = boundsOf(d);
  const seed = kind.length * 1000 + variant * 7919;
  const r = rng(seed);

  switch (kind) {
    case 'earth':
      paintPath(g, p, PAL.earth, seed, { bounds: b, spread: 0.16, volume: false });
      tufts(g, r, s, 3);
      break;
    case 'grass':
      paintPath(g, p, PAL.grass, seed, { bounds: b, spread: 0.2, volume: false });
      tufts(g, r, s, 9);
      break;
    case 'interlock': {
      paintPath(g, p, PAL.interlock, seed, { bounds: b, spread: 0.08, dabs: 40, volume: false });
      g.save();
      g.clip(p);
      g.strokeStyle = 'rgba(80,50,30,0.25)';
      g.lineWidth = 1 * s;
      for (let i = 1; i < 8; i++) {
        g.beginPath(); g.moveTo(...uv(i / 8, 0, s)); g.lineTo(...uv(i / 8, 1, s)); g.stroke();
        g.beginPath(); g.moveTo(...uv(0, i / 8, s)); g.lineTo(...uv(1, i / 8, s)); g.stroke();
      }
      g.restore();
      break;
    }
    case 'road_x':
    case 'road_y': {
      paintPath(g, p, PAL.asphalt, seed, { bounds: b, spread: 0.1, volume: false });
      g.save();
      g.clip(p);
      // Potholes: every Lagos road has them.
      const holes = Math.floor(r() * 3);
      for (let i = 0; i < holes; i++) {
        const [hx, hy] = uv(0.2 + r() * 0.6, 0.2 + r() * 0.6, s);
        g.fillStyle = 'rgba(25,20,30,0.55)';
        g.beginPath(); g.ellipse(hx, hy, (6 + r() * 8) * s, (3 + r() * 4) * s, 0, 0, Math.PI * 2); g.fill();
        g.fillStyle = 'rgba(70,90,80,0.35)'; // puddle
        g.beginPath(); g.ellipse(hx + 1 * s, hy + 1 * s, (3 + r() * 4) * s, (1.5 + r() * 2) * s, 0, 0, Math.PI * 2); g.fill();
      }
      // Faded centre dashes.
      g.strokeStyle = 'rgba(233,223,184,0.55)';
      g.lineWidth = 3 * s;
      g.setLineDash([10 * s, 12 * s]);
      g.beginPath();
      if (kind === 'road_x') { g.moveTo(...uv(0, 0.5, s)); g.lineTo(...uv(1, 0.5, s)); }
      else { g.moveTo(...uv(0.5, 0, s)); g.lineTo(...uv(0.5, 1, s)); }
      g.stroke();
      g.restore();
      break;
    }
    case 'gutter_x':
    case 'gutter_y': {
      paintPath(g, p, PAL.concrete, seed, { bounds: b, spread: 0.1, dabs: 50, volume: false });
      const ch = kind === 'gutter_x'
        ? poly([uv(0, 0.35, s), uv(1, 0.35, s), uv(1, 0.65, s), uv(0, 0.65, s)])
        : poly([uv(0.35, 0, s), uv(0.65, 0, s), uv(0.65, 1, s), uv(0.35, 1, s)]);
      paintPath(g, ch, PAL.gutterWater, seed + 3, { bounds: b, spread: 0.15, dabs: 30 });
      inkPath(g, ch, 1.2 * s, 'rgba(30,25,20,0.5)');
      break;
    }
  }
  return c;
}

function tufts(g: Ctx, r: () => number, s: number, n: number) {
  for (let i = 0; i < n; i++) {
    const [x, y] = uv(0.15 + r() * 0.7, 0.15 + r() * 0.7, s);
    g.strokeStyle = shade(PAL.grassDark, r() * 0.3);
    g.lineWidth = 1.5 * s;
    for (let k = 0; k < 4; k++) {
      g.beginPath();
      g.moveTo(x + (k - 1.5) * 2 * s, y);
      g.lineTo(x + (k - 1.5) * 3 * s + (r() - 0.5) * 3 * s, y - (4 + r() * 5) * s);
      g.stroke();
    }
  }
}

export interface BuildingSpec {
  /** Footprint in tiles along the x and y tile axes. */
  a: number;
  b: number;
  /** Wall height in px at 1x. */
  h: number;
  wall: string;
  sign?: string;
  seed: number;
}

/**
 * An isometric building: two visible painted walls, windows with burglar-proof bars,
 * a corrugated zinc roof with rust, and an optional shop sign. Returns the canvas and the
 * normalized origin (the tile-(0,0) ground corner) so the scene can place it on the grid.
 */
export function drawBuilding(spec: BuildingSpec, s: number): { canvas: HTMLCanvasElement; originX: number; originY: number } {
  const { a, b, h } = spec;
  const W = (a + b) * HALF_W * s;
  const roofRise = 10 * s;
  const H = (a + b) * HALF_H * s + h * s + roofRise;
  const { c, g } = makeCanvas(W, H);
  const r = rng(spec.seed);
  const ox = b * HALF_W * s;
  const oy = h * s + roofRise;
  const P = (x: number, y: number, z = 0): [number, number] => [ox + (x - y) * HALF_W * s, oy + (x + y) * HALF_H * s - z * s];

  blobShadow(g, ...P(a / 2 + 0.25, b / 2 + 0.25), (a + b) * HALF_W * 0.55 * s, (a + b) * HALF_H * 0.5 * s, 0.3);

  // South wall (y = b), faces down-left.
  const south: Array<[number, number]> = [P(0, b), P(a, b), P(a, b, h), P(0, b, h)];
  // East wall (x = a), faces down-right; slightly darker for form.
  const east: Array<[number, number]> = [P(a, 0), P(a, b), P(a, b, h), P(a, 0, h)];
  paintPath(g, poly(south), spec.wall, spec.seed + 1, { bounds: boundsOf(south), spread: 0.1 });
  paintPath(g, poly(east), shade(spec.wall, -0.18), spec.seed + 2, { bounds: boundsOf(east), spread: 0.1 });
  inkPath(g, poly(south), 1.2 * s);
  inkPath(g, poly(east), 1.2 * s);

  // Windows on both walls.
  const win = (face: 'south' | 'east', u: number, z0: number, ww: number, wh: number) => {
    const pts: Array<[number, number]> = face === 'south'
      ? [P(u, b, z0), P(u + ww, b, z0), P(u + ww, b, z0 + wh), P(u, b, z0 + wh)]
      : [P(a, u, z0), P(a, u + ww, z0), P(a, u + ww, z0 + wh), P(a, u, z0 + wh)];
    paintPath(g, poly(pts), PAL.window, spec.seed + u * 13, { bounds: boundsOf(pts), dabs: 6, spread: 0.2 });
    // Burglar-proof bars.
    g.strokeStyle = 'rgba(30,30,30,0.7)';
    g.lineWidth = 1 * s;
    for (let k = 1; k < 4; k++) {
      const t = u + (ww * k) / 4;
      const p0 = face === 'south' ? P(t, b, z0) : P(a, t, z0);
      const p1 = face === 'south' ? P(t, b, z0 + wh) : P(a, t, z0 + wh);
      g.beginPath(); g.moveTo(...p0); g.lineTo(...p1); g.stroke();
    }
  };
  const floors = Math.max(1, Math.floor(h / 40));
  for (let f = 0; f < floors; f++) {
    const z0 = 12 + f * 40;
    for (let u = 0.2; u < a - 0.3; u += 0.7) win('south', u, z0, 0.35, 16);
    for (let u = 0.2; u < b - 0.3; u += 0.7) win('east', u, z0, 0.35, 16);
  }

  // Door on the south wall.
  const door: Array<[number, number]> = [P(a * 0.45, b, 0), P(a * 0.45 + 0.3, b, 0), P(a * 0.45 + 0.3, b, 26), P(a * 0.45, b, 26)];
  paintPath(g, poly(door), '#5b3a26', spec.seed + 9, { bounds: boundsOf(door), dabs: 6 });

  // Corrugated zinc roof (slightly raised, with rust patches).
  const roof: Array<[number, number]> = [P(-0.08, -0.08, h + 10), P(a + 0.08, -0.08, h + 10), P(a + 0.08, b + 0.08, h + 4), P(-0.08, b + 0.08, h + 4)];
  paintPath(g, poly(roof), PAL.zinc, spec.seed + 4, { bounds: boundsOf(roof), spread: 0.12 });
  g.save();
  g.clip(poly(roof));
  g.strokeStyle = 'rgba(60,60,70,0.25)';
  g.lineWidth = 1 * s;
  for (let k = 0; k <= a * 8; k++) {
    const x = (k / 8) - 0.08;
    g.beginPath(); g.moveTo(...P(x, -0.08, h + 10)); g.lineTo(...P(x, b + 0.08, h + 4)); g.stroke();
  }
  for (let k = 0; k < 4 + a * b; k++) {
    const [rx, ry] = P(r() * a, r() * b, h + 7);
    g.fillStyle = `rgba(156,90,52,${0.25 + r() * 0.3})`;
    g.beginPath(); g.ellipse(rx, ry, (6 + r() * 10) * s, (3 + r() * 5) * s, r(), 0, Math.PI * 2); g.fill();
  }
  g.restore();
  inkPath(g, poly(roof), 1.2 * s);

  // Shop sign painted on the south wall, mapped onto the wall plane.
  if (spec.sign) {
    const sw = Math.min(a - 0.2, 1.8);
    const z = Math.min(h - 6, 44);
    const TL = P(0.1, b, z + 14), TR = P(0.1 + sw, b, z + 14), BL = P(0.1, b, z);
    const boardW = 200, boardH = 30;
    g.save();
    g.setTransform((TR[0] - TL[0]) / boardW, (TR[1] - TL[1]) / boardW, (BL[0] - TL[0]) / boardH, (BL[1] - TL[1]) / boardH, TL[0], TL[1]);
    g.fillStyle = shade(PAL.shirts[spec.seed % PAL.shirts.length]!, -0.1);
    g.fillRect(0, 0, boardW, boardH);
    g.fillStyle = '#fff6e0';
    g.font = 'bold 18px system-ui, sans-serif';
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.fillText(spec.sign, boardW / 2, boardH / 2 + 1, boardW - 10);
    g.restore();
  }

  return { canvas: c, originX: ox / W, originY: oy / H };
}

export function randomSign(seed: number): string {
  return SIGNS[seed % SIGNS.length]!;
}
