import type { FastifyInstance } from 'fastify';
import type { WebSocket } from 'ws';
import { RoomManager, TICK_HZ, sanitizeLook, sanitizeName, type Room } from './rooms.ts';
import type { Store } from './store.ts';
import { ChatHub, type ChatTarget } from './social.ts';
import { accountById, isBanned } from './account.ts';
import { ClashManager, type ClashParty } from './clash.ts';

/**
 * WebSocket protocol at /ws (JSON, compact). The first client message must be "hello".
 *
 * client → server
 *   {"t":"hello","token"?,"name","look","district","x","y"}
 *   {"t":"move","x","y","f","m","h"}        at most ~10/s, only when something changed
 *   {"t":"chat","text"}                      street chat (moderated, see social.ts)
 *   {"t":"dm","to":pid,"text"}               direct message
 *   {"t":"bump","pid"}                        my vehicle hit this player (server checks distance)
 *   {"t":"drag","pid"}                        on foot, drag this player out of their stopped vehicle and fight
 *   {"t":"clash_choice","id","choice"}        "fight" | "peace"
 *   {"t":"clash_result","id","log"}           fist-fight input log [{move,t}]
 * server → client
 *   {"t":"welcome","id","pid","room","token"?}    token only for a newly created guest
 *   {"t":"snap","meet"?:[{id,name,look,pid}],"p"?:[[id,x,y,f,m,h]],"gone"?:[id]}   ~10/s, only if non-empty
 *   {"t":"chat","id","pid","name","text","v"}  {"t":"dm","id","pid","to","name","text","sent"?}
 *   {"t":"clash","id","pid","name","ms"}  {"t":"clash_fight","id","name","seq","windows","you","them"}
 *   {"t":"clash_end","id","outcome","winner"?,"scores"?}
 *   {"t":"err","code"}
 */
const MAX_MSG_BYTES = 2048;
const MAX_MSGS_PER_SEC = 30;
const MAX_STRIKES = 40;
/** A vehicle must have stood still this long before someone on foot can drag its driver out. */
const DRAG_STILL_MS = 1500;
const DISTRICTS = new Set(['yaba', 'ikeja', 'agbado-ketu', 'oshodi', 'mushin', 'surulere', 'lagos-island', 'ikoyi', 'victoria-island', 'lekki']);

interface Session {
  socket: WebSocket;
  room?: Room;
  memberId?: number;
  playerId?: string;
  msgWindowStart: number;
  msgCount: number;
}

export function registerRealtime(app: FastifyInstance, store: Store): { rooms: RoomManager; hub: ChatHub; stop: () => void } {
  const rooms = new RoomManager();
  const sessions = new Set<Session>();
  const clashes = new ClashManager(store.db);
  const party = (s: Session): ClashParty => ({ pid: s.playerId!, name: s.room?.findPlayer(s.playerId!)?.name ?? 'Player', send: (m) => send(s, m) });
  const hub = new ChatHub(store.db, function* (): Iterable<ChatTarget> {
    for (const s of sessions) {
      if (s.playerId && s.room) yield { playerId: s.playerId, room: s.room.name, send: (m) => send(s, m) };
    }
  });

  const send = (s: Session, msg: unknown) => {
    if (s.socket.readyState === s.socket.OPEN) s.socket.send(JSON.stringify(msg));
  };

  app.get('/ws', { websocket: true }, (socket) => {
    const s: Session = { socket, msgWindowStart: Date.now(), msgCount: 0 };
    sessions.add(s);

    socket.on('message', async (raw: Buffer) => {
      // Basic flood protection: size and rate per connection.
      const now = Date.now();
      if (now - s.msgWindowStart > 1000) { s.msgWindowStart = now; s.msgCount = 0; }
      if (++s.msgCount > MAX_MSGS_PER_SEC || raw.length > MAX_MSG_BYTES) {
        send(s, { t: 'err', code: 'rate_limited' });
        return;
      }
      let msg: Record<string, unknown>;
      try {
        msg = JSON.parse(raw.toString('utf8'));
      } catch {
        send(s, { t: 'err', code: 'bad_json' });
        return;
      }

      if (msg.t === 'hello' && s.memberId === undefined) {
        const name = sanitizeName(msg.name);
        const look = sanitizeLook(msg.look);
        let token: string | undefined;
        let player = typeof msg.token === 'string' && msg.token.length < 200 ? await store.findByToken(msg.token) : null;
        if (!player) {
          const created = await store.createGuest(name, look);
          player = created.player;
          token = created.token;
        } else {
          const acct = await accountById(store.db, player.id);
          if (acct && isBanned(acct)) {
            send(s, { t: 'err', code: 'banned' });
            socket.close(4003, 'banned');
            return;
          }
          await store.touch(player.id, name, look);
        }
        const district = typeof msg.district === 'string' && DISTRICTS.has(msg.district) ? msg.district : 'yaba';
        const room = rooms.pick(district);
        s.room = room;
        s.playerId = player.id;
        s.memberId = room.join(player.id, name, look, Number(msg.x) || 0, Number(msg.y) || 0, now);
        send(s, { t: 'welcome', id: s.memberId, pid: player.id, room: room.name, ...(token ? { token } : {}) });
        return;
      }

      if (msg.t === 'move' && s.room && s.memberId !== undefined) {
        s.room.move(s.memberId, Number(msg.x), Number(msg.y), Number(msg.f) || 0, msg.m === 1 ? 1 : 0, Number(msg.h) || 0, now, msg.w === 1);
        if (s.room.strikes(s.memberId) > MAX_STRIKES) {
          send(s, { t: 'err', code: 'kicked_speed' });
          socket.close(4001, 'speed');
        }
        return;
      }

      if (msg.t === 'bump' && s.room && s.playerId && typeof msg.pid === 'string') {
        const other = [...sessions].find((o) => o.playerId === msg.pid && o.room === s.room);
        const me = s.room.findPlayer(s.playerId);
        const them = other ? s.room.findPlayer(other.playerId!) : null;
        if (!other || !me || !them) return send(s, { t: 'err', code: 'clash_gone' });
        const r = await clashes.report(party(s), party(other), me, them);
        if (r !== 'ok') send(s, { t: 'err', code: `clash_${r}` });
        return;
      }
      if (msg.t === 'drag' && s.room && s.playerId && typeof msg.pid === 'string') {
        const other = [...sessions].find((o) => o.playerId === msg.pid && o.room === s.room);
        const me = s.room.findPlayer(s.playerId, now);
        const them = other ? s.room.findPlayer(other.playerId!, now) : null;
        if (!other || !me || !them) return send(s, { t: 'err', code: 'clash_gone' });
        if (me.m !== 0) return send(s, { t: 'err', code: 'drag_get_out_first' });
        if (them.m !== 1) return send(s, { t: 'err', code: 'drag_not_driving' });
        if (them.stillMs < DRAG_STILL_MS) return send(s, { t: 'err', code: 'drag_moving' });
        const r = await clashes.drag(party(s), party(other), me, them, now);
        if (r !== 'ok') send(s, { t: 'err', code: `clash_${r}` });
        return;
      }
      if (msg.t === 'clash_choice' && s.playerId) return clashes.choose(s.playerId, msg.id, msg.choice);
      if (msg.t === 'clash_result' && s.playerId) return clashes.result(s.playerId, msg.id, msg.log);

      if ((msg.t === 'chat' || msg.t === 'dm') && s.room && s.playerId) {
        const me: ChatTarget = { playerId: s.playerId, room: s.room.name, send: (m) => send(s, m) };
        if (msg.t === 'chat') await hub.chat(me, msg.text);
        else await hub.dm(me, msg.to, msg.text);
        return;
      }

      send(s, { t: 'err', code: 'unexpected' });
    });

    socket.on('close', () => {
      if (s.playerId) clashes.left(s.playerId);
      if (s.room && s.memberId !== undefined) s.room.leave(s.memberId);
      sessions.delete(s);
      rooms.prune();
    });
  });

  // Broadcast loop: each player gets only nearby players that changed.
  const timer = setInterval(() => {
    for (const s of sessions) {
      if (!s.room || s.memberId === undefined) continue;
      const snap = s.room.snapshotFor(s.memberId);
      if (snap.meet.length === 0 && snap.rows.length === 0 && snap.gone.length === 0) continue;
      send(s, {
        t: 'snap',
        ...(snap.meet.length ? { meet: snap.meet } : {}),
        ...(snap.rows.length ? { p: snap.rows } : {}),
        ...(snap.gone.length ? { gone: snap.gone } : {}),
      });
    }
  }, 1000 / TICK_HZ);

  // Keep connections alive through Cloudflare's ~100 s idle timeout.
  const ping = setInterval(() => {
    for (const s of sessions) if (s.socket.readyState === s.socket.OPEN) s.socket.ping();
  }, 30_000);

  return {
    rooms,
    hub,
    stop: () => {
      clearInterval(timer);
      clearInterval(ping);
    },
  };
}
