import type { TileKind } from '../art/tiles';
import { PAL } from '../art/palette';
import { rng } from '../art/paint';

/**
 * M0 style-test map: one Yaba junction. A main road with gutters and interlocked
 * walkways, a cross street, painted buildings with shop signs, POS umbrellas, poles
 * and generators. Fully deterministic.
 */
export const MAP_SIZE = 28;
export const CHUNK = 7; // tiles per streaming chunk (draw distance unit)

export interface Building { tx: number; ty: number; a: number; b: number; h: number; wall: string; sign?: string; seed: number; generator: boolean }
export interface Prop { kind: 'umbrella' | 'pole' | 'transformer' | 'generator' | 'palm'; tx: number; ty: number; seed: number }

export interface WorldData {
  tiles: TileKind[][]; // [ty][tx]
  blocked: boolean[][];
  buildings: Building[];
  props: Prop[];
  danfoStart: { tx: number; ty: number; heading: number };
  playerStart: { tx: number; ty: number };
}

const MAIN = [12, 13]; // road rows (ty) for the x-axis road
const CROSS = [12, 13]; // road columns (tx) for the y-axis road

export function isRoad(t: TileKind): boolean {
  return t === 'road_x' || t === 'road_y';
}

export function buildYaba(): WorldData {
  const r = rng(2026);
  const tiles: TileKind[][] = [];
  const blocked: boolean[][] = [];
  for (let ty = 0; ty < MAP_SIZE; ty++) {
    tiles.push([]);
    blocked.push([]);
    for (let tx = 0; tx < MAP_SIZE; tx++) {
      // Grass grows in patches (smooth field), not as random speckle.
      const field = Math.sin(tx * 0.55 + 1.3) + Math.cos(ty * 0.45 - 0.7) + Math.sin((tx + ty) * 0.3) * 0.8 + (r() - 0.5) * 0.6;
      let k: TileKind = field > 0.9 ? 'grass' : 'earth';
      const onMain = MAIN.includes(ty);
      const onCross = CROSS.includes(tx);
      if (onMain && onCross) k = 'road_x';
      else if (onMain) k = 'road_x';
      else if (onCross) k = 'road_y';
      else if ((ty === 11 || ty === 14) && !onCross && tx !== 11 && tx !== 14) k = 'gutter_x';
      else if ((tx === 11 || tx === 14) && !onMain && ty !== 11 && ty !== 14) k = 'gutter_y';
      else if (ty === 10 || ty === 15 || tx === 10 || tx === 15) k = 'interlock';
      tiles[ty]!.push(k);
      blocked[ty]!.push(false);
    }
  }

  const buildings: Building[] = [];
  const signs = ['AUNTY BOSS KITCHEN', 'KONFAM POS', 'GIDI BARBING SALON', '9BARS RECHARGE', "GOD'S TIME PHONE REPAIRS", 'MIRACLE FM 99.9', 'TAP-TAP POS', undefined];
  // Blocks: four quadrants around the junction.
  const lots: Array<[number, number, number, number, number]> = [
    // tx, ty, a, b, height
    [3, 6, 3, 3, 70], [7, 6, 2, 3, 46], [17, 6, 3, 3, 90], [21, 6, 3, 3, 52], [25, 7, 2, 2, 44],
    [3, 17, 3, 3, 52], [7, 17, 2, 2, 44], [17, 17, 2, 3, 70], [20, 17, 3, 3, 46], [24, 18, 3, 2, 60],
    [2, 1, 3, 2, 44], [17, 1, 3, 3, 52], [3, 22, 3, 3, 90], [18, 23, 3, 3, 46], [22, 22, 3, 2, 52],
  ];
  lots.forEach(([tx, ty, a, b, h], i) => {
    const seed = 100 + i * 31;
    buildings.push({ tx, ty, a, b, h, wall: PAL.walls[i % PAL.walls.length]!, sign: signs[i % signs.length], seed, generator: i % 3 === 0 });
    for (let y = ty; y < ty + b; y++) for (let x = tx; x < tx + a; x++) if (blocked[y]) blocked[y]![x] = true;
  });

  const props: Prop[] = [];
  // POS umbrellas line the walkways.
  [[9, 10], [16, 10], [20, 15], [6, 15], [10, 16], [16, 9]].forEach(([tx, ty], i) => props.push({ kind: 'umbrella', tx: tx!, ty: ty!, seed: i }));
  // Poles every few tiles, one with a transformer.
  for (let tx = 2; tx < MAP_SIZE; tx += 5) props.push({ kind: tx === 17 ? 'transformer' : 'pole', tx, ty: 10, seed: tx });
  for (let ty = 2; ty < MAP_SIZE; ty += 5) if (ty < 9 || ty > 16) props.push({ kind: 'pole', tx: 15, ty, seed: 50 + ty });
  // Generators beside the buildings that own one.
  buildings.filter((b) => b.generator).forEach((b, i) => props.push({ kind: 'generator', tx: b.tx + b.a, ty: b.ty + b.b - 1, seed: 300 + i }));
  // Palms in some grass.
  for (let i = 0; i < 14; i++) {
    const tx = Math.floor(r() * MAP_SIZE), ty = Math.floor(r() * MAP_SIZE);
    if (tiles[ty]![tx] === 'grass' && !blocked[ty]![tx]) props.push({ kind: 'palm', tx, ty, seed: 400 + i });
  }
  for (const p of props) if (p.kind !== 'umbrella') blocked[p.ty]![p.tx] = true;

  return {
    tiles,
    blocked,
    buildings,
    props,
    danfoStart: { tx: 5.5, ty: 12.5, heading: 0 },
    playerStart: { tx: 7.5, ty: 15.5 },
  };
}
