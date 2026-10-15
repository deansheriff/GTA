/**
 * Shared-street rooms (pure logic, no sockets): who is in which district room, validated movement,
 * and per-player snapshots that only contain nearby players who changed.
 *
 * Data budget (proposal §8): idle players cost ~0 bytes; a busy street costs a few KB/s at most.
 */

export const TICK_HZ = 10;
export const ROOM_CAPACITY = 80;
/** Players farther than this (px) are not sent to you. About two screens wide. */
export const INTEREST_RADIUS = 1600;
/** Max speeds (px/s) with slack for network jitter. Walking 150, danfo 380 in the client. */
const MAX_SPEED = { walk: 240, drive: 520 } as const;
// Tropical-island Lagos: 192 × 132 cells of 64 px (game/data/map/lagos.json).
const WORLD = { w: 192 * 64, h: 132 * 64 };
/** Fast travel (keke, story scenes, hero switches) may jump once every few seconds without a strike. */
const WARP_COOLDOWN_MS = 3000;

export type Mode = 0 | 1; // 0 walking, 1 driving

export interface PublicInfo {
  id: number;
  name: string;
  look: Record<string, unknown>;
  pid?: string;
}

/** Compact state row sent to clients: [id, x, y, facing, mode, heading°]. */
export type Row = [number, number, number, number, Mode, number];

interface Member extends PublicInfo {
  playerId: string; // stable account id; shared as `pid` so players can DM, block and report
  x: number;
  y: number;
  f: number;
  m: Mode;
  h: number;
  lastMoveAt: number;
  lastWarpAt: number;
  stillSince: number; // last time the player actually changed position (drag-outs need a stopped vehicle)
  version: number; // increments on every accepted move
  seen: Map<number, number>; // other member id -> version last sent to this member
  strikes: number;
}

export interface Snapshot {
  meet: PublicInfo[]; // newly visible players (send names/looks once)
  rows: Row[]; // positions of visible players that changed
  gone: number[]; // players no longer visible (left or out of range)
}

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));

export class Room {
  readonly name: string;
  private members = new Map<number, Member>();
  private nextId = 1;

  constructor(name: string) {
    this.name = name;
  }

  get size(): number {
    return this.members.size;
  }

  get isFull(): boolean {
    return this.members.size >= ROOM_CAPACITY;
  }

  join(playerId: string, name: string, look: Record<string, unknown>, x: number, y: number, now: number): number {
    const id = this.nextId++;
    this.members.set(id, {
      id, playerId, name: sanitizeName(name), look: sanitizeLook(look),
      x: clamp(x, 0, WORLD.w), y: clamp(y, 0, WORLD.h), f: 0, m: 0, h: 0,
      lastMoveAt: now, lastWarpAt: 0, stillSince: now, version: 1, seen: new Map(), strikes: 0,
    });
    return id;
  }

  leave(id: number): void {
    this.members.delete(id);
  }

  /**
   * Accept a move if it is physically possible since the last accepted one; otherwise keep the
   * server position (the client will be corrected by its own echo). Returns false when rejected.
   */
  move(id: number, x: number, y: number, f: number, m: Mode, h: number, now: number, warp = false): boolean {
    const p = this.members.get(id);
    if (!p || !Number.isFinite(x) || !Number.isFinite(y)) return false;
    const dt = Math.max(0.05, (now - p.lastMoveAt) / 1000);
    const dist = Math.hypot(x - p.x, y - p.y);
    // 48 px of slack absorbs network jitter and the first move after joining.
    const limit = MAX_SPEED[m === 1 ? 'drive' : 'walk'] * dt + 48;
    const warpOk = warp && now - p.lastWarpAt >= WARP_COOLDOWN_MS;
    if (warpOk) p.lastWarpAt = now;
    if (dist > limit && !warpOk) {
      p.strikes++;
      return false;
    }
    if (dist > 6) p.stillSince = now;
    p.x = clamp(Math.round(x), 0, WORLD.w);
    p.y = clamp(Math.round(y), 0, WORLD.h);
    p.f = clamp(Math.round(f), 0, 3);
    p.m = m === 1 ? 1 : 0;
    p.h = ((Math.round(h) % 360) + 360) % 360;
    p.lastMoveAt = now;
    p.version++;
    return true;
  }

  /** A player changed their style: everyone nearby is re-introduced to them with the new look. */
  setLook(id: number, look: unknown): void {
    const p = this.members.get(id);
    if (!p) return;
    p.look = sanitizeLook(look);
    for (const other of this.members.values()) other.seen.delete(id);
  }

  /** Server-side position of an account in this room (for clash checks). `stillMs`: time since it last moved. */
  findPlayer(playerId: string, now = Date.now()): { id: number; x: number; y: number; m: Mode; name: string; stillMs: number } | null {
    for (const p of this.members.values()) {
      if (p.playerId === playerId) return { id: p.id, x: p.x, y: p.y, m: p.m, name: p.name, stillMs: now - p.stillSince };
    }
    return null;
  }

  strikes(id: number): number {
    return this.members.get(id)?.strikes ?? 0;
  }

  /** What member `id` should receive this tick. Mutates its "seen" bookkeeping. */
  snapshotFor(id: number): Snapshot {
    const me = this.members.get(id);
    const out: Snapshot = { meet: [], rows: [], gone: [] };
    if (!me) return out;
    for (const [otherId, other] of this.members) {
      if (otherId === id) continue;
      const near = Math.hypot(other.x - me.x, other.y - me.y) <= INTEREST_RADIUS;
      const sentVersion = me.seen.get(otherId);
      if (!near) {
        if (sentVersion !== undefined) {
          out.gone.push(otherId);
          me.seen.delete(otherId);
        }
        continue;
      }
      if (sentVersion === undefined) {
        out.meet.push({ id: other.id, name: other.name, look: other.look, pid: other.playerId });
      }
      if (sentVersion !== other.version) {
        out.rows.push([other.id, other.x, other.y, other.f, other.m, other.h]);
        me.seen.set(otherId, other.version);
      }
    }
    for (const seenId of me.seen.keys()) {
      if (!this.members.has(seenId)) {
        out.gone.push(seenId);
        me.seen.delete(seenId);
      }
    }
    return out;
  }

  memberIds(): number[] {
    return [...this.members.keys()];
  }
}

/** Fills rooms in order; opens "yaba-2", "yaba-3"... when a room is full. */
export class RoomManager {
  private rooms = new Map<string, Room>();

  pick(district: string): Room {
    for (let i = 1; ; i++) {
      const key = `${district}-${i}`;
      let room = this.rooms.get(key);
      if (!room) {
        room = new Room(key);
        this.rooms.set(key, room);
      }
      if (!room.isFull) return room;
    }
  }

  all(): Room[] {
    return [...this.rooms.values()];
  }

  /** Drop empty overflow rooms so they don't accumulate. */
  prune(): void {
    for (const [key, room] of this.rooms) if (room.size === 0 && !key.endsWith('-1')) this.rooms.delete(key);
  }
}

export function sanitizeName(name: unknown): string {
  const s = String(name ?? '').replace(/[\u0000-\u001f<>]/g, '').trim().slice(0, 20);
  return s || 'Lagosian';
}

/** Only allow known look keys with short string/colour values: nothing else is relayed. */
export function sanitizeLook(look: unknown): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  if (!look || typeof look !== 'object') return out;
  // Style (M10): outfit id, cap colour, bus paint, slogan index (from a fixed list), crew tag (M11).
  const allowed = ['skin', 'top', 'bottom', 'hair', 'hair_col', 'extra', 'outfit', 'cap', 'bus', 'sl', 'crew'];
  for (const k of allowed) {
    const v = (look as Record<string, unknown>)[k];
    if (typeof v === 'string' && v.length <= 16 && /^[#a-zA-Z0-9_]+$/.test(v)) out[k] = v;
  }
  return out;
}
