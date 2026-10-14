#!/usr/bin/env node
// Test bots: N players who wander near a point, for multiplayer and load testing.
//   node scripts/bots.mjs ws://127.0.0.1:8787 3 [seconds]
import WebSocket from 'ws';

const [base = 'ws://127.0.0.1:8787', countArg = '3', secondsArg = '60'] = process.argv.slice(2);
const url = base.replace(/^http/, 'ws').replace(/\/$/, '') + (base.endsWith('/ws') ? '' : '/ws');
const names = ['Sule', 'Mama Nkem', 'Pepper', 'Salt', 'Officer Gbenga', 'Teacher', 'Bayo'];
const looks = [{ top: '#22806f', hair: 'cap', hair_col: '#c96f24' }, { top: '#c96f24', bottom: '#c96f24', hair: 'gele', hair_col: '#1f9a86', extra: 'wrapper' }, { top: '#76418a', hair: 'afro' }];
let received = 0;

for (let i = 0; i < Number(countArg); i++) {
  const ws = new WebSocket(url);
  let x = 700 + i * 60, y = 1080, tx = x, ty = y, f = 0;
  ws.on('open', () => ws.send(JSON.stringify({ t: 'hello', name: names[i % names.length], look: looks[i % looks.length], x, y })));
  ws.on('message', (d) => { received += d.length; });
  setInterval(() => {
    if (Math.hypot(tx - x, ty - y) < 6) { tx = 560 + Math.random() * 400; ty = 1060 + Math.random() * 80; }
    const dx = tx - x, dy = ty - y, d = Math.hypot(dx, dy) || 1;
    x += (dx / d) * 9; y += (dy / d) * 9; // 90 px/s at 10 Hz
    f = Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? 2 : 3) : dy > 0 ? 0 : 1;
    if (ws.readyState === ws.OPEN) ws.send(JSON.stringify({ t: 'move', x: Math.round(x), y: Math.round(y), f, m: 0, h: 0 }));
  }, 100);
}
setTimeout(() => { console.log(`bots done; received ${received} bytes`); process.exit(0); }, Number(secondsArg) * 1000);
