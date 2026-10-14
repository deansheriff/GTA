#!/usr/bin/env node
/**
 * Applies native-speaker corrections back into the game data:
 *   node tools/import_review.mjs docs/review/lines-for-review.csv
 * Only rows with a non-empty "reviewer_correction" change anything. Prints every change.
 */
import { readFileSync, writeFileSync } from 'node:fs';

const file = process.argv[2] ?? 'docs/review/lines-for-review.csv';
const text = readFileSync(file, 'utf8').replace(/^﻿/, '');

// Minimal RFC-4180 CSV parser (quoted fields, doubled quotes, newlines inside quotes).
function parse(s) {
  const rows = [];
  let row = [], field = '', q = false;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (q) {
      if (c === '"' && s[i + 1] === '"') { field += '"'; i++; }
      else if (c === '"') q = false;
      else field += c;
    } else if (c === '"') q = true;
    else if (c === ',') { row.push(field); field = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && s[i + 1] === '\n') i++;
      row.push(field); rows.push(row); row = []; field = '';
    } else field += c;
  }
  if (field || row.length) { row.push(field); rows.push(row); }
  return rows;
}

const paths = { dialogue: 'game/data/story/dialogue.json', chat: 'game/data/story/chat.json', cast: 'game/data/story/cast.json' };
const data = Object.fromEntries(Object.entries(paths).map(([k, p]) => [k, JSON.parse(readFileSync(p, 'utf8'))]));
let changed = 0;
const set = (obj, keyPath, value) => {
  let o = obj;
  for (let i = 0; i < keyPath.length - 1; i++) o = o?.[keyPath[i]];
  if (!o || !(keyPath[keyPath.length - 1] in o)) return false;
  o[keyPath[keyPath.length - 1]] = value;
  return true;
};

for (const [id, , , original, fix] of parse(text).slice(1)) {
  if (!fix || !fix.trim() || fix.trim() === original) continue;
  const p = id.split('.');
  let ok = false;
  if (p[0] === 'dlg') {
    // dlg.<key>.<i>[.choiceK[.replyM]]
    const base = ['lines', p[1], Number(p[2])];
    if (p.length === 3) ok = set(data.dialogue, [...base, 'text'], fix);
    else if (p.length === 4) ok = set(data.dialogue, [...base, 'choices', Number(p[3].slice(6)), 'text'], fix);
    else ok = set(data.dialogue, [...base, 'choices', Number(p[3].slice(6)), 'reply', Number(p[4].slice(5)), 'text'], fix);
  } else if (p[0] === 'chat') ok = set(data.chat, ['scripted', p[1], Number(p[2]), 'text'], fix);
  else if (p[0] === 'switch') ok = set(data.chat, ['switch', p[1], Number(p[2]), Number(p[3]), 'text'], fix);
  else if (p[0] === 'switch_cold') ok = set(data.chat, ['switch_cold', Number(p[1]), Number(p[2]), 'text'], fix);
  else if (p[0] === 'banter') ok = set(data.chat, ['banter', p[1], Number(p[2])], fix);
  else if (p[0] === 'chatter') ok = set(data.cast, ['cast', p[1], 'chatter', Number(p[2])], fix);
  else if (p[0] === 'offscreen') {
    const e = data.chat.offscreen.find((x) => x.id === p[1]);
    if (e) { e.text = fix; ok = true; }
  }
  if (ok) { changed++; console.log(`${id}: "${original}" → "${fix}"`); }
  else console.warn(`skipped ${id} (not found)`);
}
for (const [k, p] of Object.entries(paths)) writeFileSync(p, JSON.stringify(data[k], null, 2) + '\n');
console.log(`${changed} line(s) updated`);
