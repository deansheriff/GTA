#!/usr/bin/env node
// Smoke test for a running server: health, then two WebSocket players see each other.
//   node scripts/smoke-ws.mjs https://game.example.com
import WebSocket from 'ws';

const base = (process.argv[2] ?? 'http://127.0.0.1:8787').replace(/\/$/, '');
const wsUrl = base.replace(/^http/, 'ws') + '/ws';
const fail = (m) => { console.error('✗', m); process.exit(1); };
setTimeout(() => fail('timed out'), 15000);

const health = await fetch(base + '/api/health').then((r) => r.json()).catch((e) => fail('health: ' + e.message));
if (!health.ok) fail('health not ok: ' + JSON.stringify(health));
console.log('✓ health', JSON.stringify(health));

const open = (name, x) => new Promise((resolve, reject) => {
  const ws = new WebSocket(wsUrl);
  ws.on('error', reject);
  ws.on('open', () => ws.send(JSON.stringify({ t: 'hello', name, look: {}, x, y: 1000 })));
  ws.on('message', (d) => { const m = JSON.parse(String(d)); if (m.t === 'welcome') resolve({ ws, m }); });
});
const a = await open('SmokeA', 600);
const seen = new Promise((resolve) => a.ws.on('message', (d) => { const m = JSON.parse(String(d)); if (m.meet?.some((p) => p.name === 'SmokeB')) resolve(); }));
const b = await open('SmokeB', 650);
await seen;
console.log('✓ realtime: two players in', a.m.room, 'see each other');
a.ws.close(); b.ws.close();
process.exit(0);
