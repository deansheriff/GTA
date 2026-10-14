/** Isometric constants and helpers. 2:1 projection; one tile is 128x64 at 1x. */
export const TILE_W = 128;
export const TILE_H = 64;
export const HALF_W = TILE_W / 2;
export const HALF_H = TILE_H / 2;

/** Tile coords (can be fractional) to world pixel coords (top vertex of the tile diamond). */
export function tileToWorld(tx: number, ty: number): { x: number; y: number } {
  return { x: (tx - ty) * HALF_W, y: (tx + ty) * HALF_H };
}

/** World pixel coords to fractional tile coords. */
export function worldToTile(x: number, y: number): { tx: number; ty: number } {
  return { tx: (x / HALF_W + y / HALF_H) / 2, ty: (y / HALF_H - x / HALF_W) / 2 };
}

/** The 8 compass directions in screen terms, indexed by world heading (0 = +x tile axis = screen SE). */
export const DIRS8 = ['se', 's', 'sw', 'w', 'nw', 'n', 'ne', 'e'] as const;
export type Dir8 = (typeof DIRS8)[number];

/** Heading angle in tile space (radians) to direction index 0..7. */
export function headingToDir(angle: number): number {
  const a = ((angle % (Math.PI * 2)) + Math.PI * 2) % (Math.PI * 2);
  return Math.round(a / (Math.PI / 4)) % 8;
}
