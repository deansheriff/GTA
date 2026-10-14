#!/usr/bin/env node
/**
 * Exports every scripted line for native-speaker review (Story Bible §10 🔒):
 *   node tools/export_review.mjs   →   docs/review/lines-for-review.csv
 * Columns: id, where, speaker, text, reviewer_correction, reviewer_notes. Reviewers fill the
 * last two columns; tools/import_review.mjs (later) applies corrections back into the JSON.
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';

const j = (p) => JSON.parse(readFileSync(p, 'utf8'));
const dialogue = j('game/data/story/dialogue.json').lines;
const chat = j('game/data/story/chat.json');
const cast = j('game/data/story/cast.json').cast;
const rows = [['id', 'where', 'speaker', 'text', 'reviewer_correction', 'reviewer_notes']];
const csv = (s) => `"${String(s ?? '').replace(/"/g, '""')}"`;

for (const [key, lines] of Object.entries(dialogue)) {
  lines.forEach((l, i) => {
    rows.push([`dlg.${key}.${i}`, 'story dialogue', l.who, l.text]);
    (l.choices ?? []).forEach((c, k) => {
      rows.push([`dlg.${key}.${i}.choice${k}`, 'story choice', l.who, c.text]);
      (c.reply ?? []).forEach((r, m) => rows.push([`dlg.${key}.${i}.choice${k}.reply${m}`, 'story reply', r.who, r.text]));
    });
  });
}
for (const [key, lines] of Object.entries(chat.scripted ?? {})) lines.forEach((l, i) => rows.push([`chat.${key}.${i}`, 'family chat', l.who, l.text]));
for (const [hero, convos] of Object.entries(chat.switch ?? {})) convos.forEach((c, k) => c.forEach((l, i) => rows.push([`switch.${hero}.${k}.${i}`, 'switch chat', l.who, l.text])));
(chat.switch_cold ?? []).forEach((c, k) => c.forEach((l, i) => rows.push([`switch_cold.${k}.${i}`, 'switch chat', l.who, l.text])));
for (const e of chat.offscreen ?? []) rows.push([`offscreen.${e.id}`, 'off-screen event', '', e.text]);
for (const [bank, lines] of Object.entries(chat.banter ?? {})) lines.forEach((t, i) => rows.push([`banter.${bank}.${i}`, 'banter', '', t]));
for (const v of chat.votes ?? []) rows.push([`vote.${v.q}`, 'passenger vote', '', `${v.q} / ${v.a} / ${v.b}`]);
for (const [who, c] of Object.entries(cast)) (c.chatter ?? []).forEach((t, i) => rows.push([`chatter.${who}.${i}`, 'NPC chatter', who, t]));

mkdirSync('docs/review', { recursive: true });
writeFileSync('docs/review/lines-for-review.csv', '﻿' + rows.map((r) => r.map(csv).join(',')).join('\n') + '\n');
console.log(`docs/review/lines-for-review.csv: ${rows.length - 1} lines`);
