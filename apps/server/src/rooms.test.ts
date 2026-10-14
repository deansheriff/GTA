import { test } from 'node:test';
import assert from 'node:assert/strict';
import { INTEREST_RADIUS, ROOM_CAPACITY, Room, RoomManager, sanitizeLook, sanitizeName } from './rooms.ts';

test('a new nearby player is met once, then only sent when they move', () => {
  const room = new Room('yaba-1');
  const a = room.join('pa', 'Tunde', {}, 100, 100, 0);
  const b = room.join('pb', 'Ngozi', {}, 200, 100, 0);
  let snap = room.snapshotFor(a);
  assert.equal(snap.meet.length, 1);
  assert.equal(snap.meet[0]!.name, 'Ngozi');
  assert.equal(snap.rows.length, 1);
  snap = room.snapshotFor(a);
  assert.deepEqual(snap, { meet: [], rows: [], gone: [] }, 'idle players cost nothing');
  assert.ok(room.move(b, 230, 100, 1, 0, 0, 500));
  snap = room.snapshotFor(a);
  assert.deepEqual(snap.rows, [[b, 230, 100, 1, 0, 0]]);
});

test('teleport-sized moves are rejected and counted', () => {
  const room = new Room('yaba-1');
  const a = room.join('pa', 'KC', {}, 100, 100, 0);
  assert.equal(room.move(a, 2000, 1500, 0, 0, 0, 100), false);
  assert.equal(room.strikes(a), 1);
  assert.equal(room.move(a, 120, 100, 0, 0, 0, 200), true, 'a normal step is fine');
  // Driving allows faster movement than walking.
  assert.equal(room.move(a, 120 + 400, 100, 0, 1, 0, 1200), true);
});

test('players out of range are not sent, and leaving players are reported gone', () => {
  const room = new Room('yaba-1');
  const a = room.join('pa', 'A', {}, 0, 0, 0);
  const far = room.join('pb', 'B', {}, INTEREST_RADIUS + 300, 0, 0);
  assert.equal(room.snapshotFor(a).meet.length, 0);
  const near = room.join('pc', 'C', {}, 50, 50, 0);
  assert.equal(room.snapshotFor(a).meet.length, 1);
  room.leave(near);
  assert.deepEqual(room.snapshotFor(a).gone, [near]);
  assert.ok(far > 0);
});

test('rooms overflow into a second room when full', () => {
  const rm = new RoomManager();
  const first = rm.pick('yaba');
  for (let i = 0; i < ROOM_CAPACITY; i++) first.join(`p${i}`, 'x', {}, 10, 10, 0);
  assert.equal(rm.pick('yaba').name, 'yaba-2');
});

test('names and looks are sanitized before relaying', () => {
  assert.equal(sanitizeName('<script>alert(1)</script>'), 'scriptalert(1)/scrip');
  assert.equal(sanitizeName('   '), 'Lagosian');
  assert.deepEqual(sanitizeLook({ skin: '#4f3121', evil: 'x', hair: 'low; drop table' }), { skin: '#4f3121' });
});
