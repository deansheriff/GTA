#!/usr/bin/env node
/**
 * Synthesises every sound in the game from code (no samples, no licences needed):
 *   node tools/audio/synth.mjs   →   game/audio/{sfx,amb,music}/*.wav
 * 22.05 kHz mono 16-bit keeps the whole set small. Licensed music can replace the loops later
 * (drop files with the same names into game/audio/music/ — owner's licensing 🔒).
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

const SR = 22050;
const OUT = 'game/audio';
let seed = 1337;
const rand = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff) * 2 - 1;

function wav(file, samples) {
  const n = samples.length;
  const buf = Buffer.alloc(44 + n * 2);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + n * 2, 4); buf.write('WAVE', 8);
  buf.write('fmt ', 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(1, 22);
  buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 2, 28); buf.writeUInt16LE(2, 32); buf.writeUInt16LE(16, 34);
  buf.write('data', 36); buf.writeUInt32LE(n * 2, 40);
  let peak = 0;
  for (const s of samples) peak = Math.max(peak, Math.abs(s));
  const g = peak > 0.98 ? 0.98 / peak : 1;
  for (let i = 0; i < n; i++) buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, samples[i] * g)) * 32767), 44 + i * 2);
  const path = join(OUT, file);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, buf);
  console.log(`${path} ${(buf.length / 1024).toFixed(0)} KB`);
}

const len = (sec) => new Float32Array(Math.round(sec * SR));
const env = (i, n, a = 0.01, r = 0.2) => {
  const t = i / SR, d = n / SR;
  return Math.min(1, t / a) * Math.min(1, Math.max(0, (d - t) / r));
};
const sq = (ph) => (ph % 1 < 0.5 ? 1 : -1);
const saw = (ph) => 2 * (ph % 1) - 1;
const tri = (ph) => 1 - 4 * Math.abs((ph % 1) - 0.5);
/** One-pole low-pass in place. */
function lowpass(x, cut) {
  const a = Math.exp(-2 * Math.PI * cut / SR);
  let y = 0;
  for (let i = 0; i < x.length; i++) { y = (1 - a) * x[i] + a * y; x[i] = y; }
  return x;
}
function mix(dst, src, at = 0, gain = 1) {
  const o = Math.round(at * SR);
  for (let i = 0; i < src.length && o + i < dst.length; i++) dst[o + i] += src[i] * gain;
  return dst;
}
/** Karplus–Strong pluck: a warm guitar-ish note for the highlife/afrobeat loops. */
function pluck(freq, sec, bright = 0.5) {
  const out = len(sec);
  const p = Math.max(2, Math.round(SR / freq));
  const ring = new Float32Array(p);
  for (let i = 0; i < p; i++) ring[i] = rand() * bright;
  for (let i = 0, k = 0; i < out.length; i++, k = (k + 1) % p) {
    const next = ring[(k + 1) % p];
    out[i] = ring[k];
    ring[k] = 0.996 * 0.5 * (ring[k] + next);
  }
  return out;
}
function kick(sec = 0.35) {
  const x = len(sec);
  let ph = 0;
  for (let i = 0; i < x.length; i++) { const t = i / SR; ph += (55 + 120 * Math.exp(-t * 30)) / SR; x[i] = Math.sin(2 * Math.PI * ph) * Math.exp(-t * 9); }
  return x;
}
function clap(sec = 0.2) {
  const x = len(sec);
  for (let i = 0; i < x.length; i++) { const t = i / SR; x[i] = rand() * (Math.exp(-t * 25) + 0.5 * Math.exp(-Math.abs(t - 0.012) * 300)); }
  return lowpass(x, 3000);
}
function shaker(sec = 0.06) {
  const x = len(sec);
  let prev = 0;
  for (let i = 0; i < x.length; i++) { const n = rand(); x[i] = (n - prev) * Math.exp(-(i / SR) * 60) * 0.6; prev = n; }
  return x;
}
function bassNote(freq, sec) {
  const x = len(sec);
  for (let i = 0; i < x.length; i++) x[i] = (Math.sin(2 * Math.PI * freq * i / SR) + 0.3 * tri(freq * i / SR)) * env(i, x.length, 0.005, 0.08);
  return x;
}

// ---------- sound effects ----------
{
  // Danfo "goat horn": two detuned square tones with a wobble.
  const x = len(0.7);
  for (let i = 0; i < x.length; i++) {
    const t = i / SR, v = 1 + 0.03 * Math.sin(2 * Math.PI * 7 * t);
    x[i] = (sq(380 * v * t) + 0.8 * sq(478 * v * t)) * 0.3 * env(i, x.length, 0.02, 0.12);
  }
  wav('sfx/horn.wav', lowpass(x, 2500));
}
{
  const x = len(0.06);
  for (let i = 0; i < x.length; i++) x[i] = Math.sin(2 * Math.PI * 1400 * i / SR) * env(i, x.length, 0.002, 0.05) * 0.6;
  wav('sfx/tap.wav', x);
}
{
  // Cash register: a drawer clunk then a bell.
  const x = len(0.9);
  mix(x, clap(0.08), 0, 0.8);
  for (const [f, g] of [[2093, 0.5], [2637, 0.35], [3136, 0.25]]) {
    const b = len(0.8);
    for (let i = 0; i < b.length; i++) b[i] = Math.sin(2 * Math.PI * f * i / SR) * Math.exp(-(i / SR) * 5) * g;
    mix(x, b, 0.08);
  }
  wav('sfx/cash.wav', x);
}
{
  // UP NEPA: transformer thunk, hum swelling up, a little sparkle.
  const x = len(1.4);
  mix(x, kick(0.4), 0, 0.9);
  let ph = 0;
  for (let i = 0; i < x.length; i++) {
    const t = i / SR; ph += (40 + 80 * Math.min(1, t / 0.8)) / SR;
    x[i] += (saw(ph) * 0.25 + saw(ph * 2) * 0.1) * Math.min(1, t / 0.3) * env(i, x.length, 0.01, 0.4);
  }
  for (let k = 0; k < 4; k++) mix(x, pluck(880 * [1, 1.25, 1.5, 2][k], 0.6, 0.8), 0.6 + k * 0.08, 0.35);
  wav('sfx/power_on.wav', lowpass(x, 5000));
}
{
  const x = len(1.0);
  let ph = 0;
  for (let i = 0; i < x.length; i++) { const t = i / SR; ph += (120 * Math.exp(-t * 3) + 20) / SR; x[i] = saw(ph) * 0.4 * env(i, x.length, 0.005, 0.5); }
  wav('sfx/power_off.wav', lowpass(x, 1500));
}
{
  const x = len(0.5);
  mix(x, kick(0.5), 0, 1);
  const n = len(0.3);
  for (let i = 0; i < n.length; i++) n[i] = rand() * Math.exp(-(i / SR) * 18);
  mix(x, lowpass(n, 1800), 0, 0.8);
  wav('sfx/crash.wav', x);
}
{
  const x = len(1.0);
  [523, 659, 784, 1047].forEach((f, k) => mix(x, pluck(f, 0.7, 0.7), k * 0.09, 0.6));
  wav('sfx/success.wav', x);
}
{
  const x = len(0.9);
  let ph = 0;
  for (let i = 0; i < x.length; i++) { const t = i / SR; ph += (330 - 160 * t) / SR; x[i] = sq(ph) * 0.25 * (0.6 + 0.4 * Math.sin(2 * Math.PI * 6 * t)) * env(i, x.length, 0.01, 0.3); }
  wav('sfx/fail.wav', lowpass(x, 1800));
}
{
  const x = len(1.2);
  for (let i = 0; i < x.length; i++) { const t = i / SR; x[i] = (Math.sin(2 * Math.PI * 110 * t) + 0.5 * Math.sin(2 * Math.PI * 116.5 * t)) * 0.4 * env(i, x.length, 0.15, 0.4); }
  wav('sfx/stare.wav', x);
}
{
  const x = len(0.8);
  for (let i = 0; i < x.length; i++) x[i] = rand() * Math.sin(Math.PI * i / x.length) * 0.7;
  wav('sfx/whoosh.wav', lowpass(x, 1200));
}
{
  const x = len(0.35);
  mix(x, pluck(1318, 0.3, 0.9), 0, 0.7);
  mix(x, pluck(1760, 0.25, 0.9), 0.09, 0.6);
  wav('sfx/notify.wav', x);
}

// ---------- ambience loops (seamless: whole cycles) ----------
{
  // Generator: 50 Hz-ish rumble with harmonics, cylinder knocks, a bit of exhaust noise.
  const x = len(2.0);
  for (let i = 0; i < x.length; i++) {
    const t = i / SR;
    x[i] = 0.35 * saw(50 * t) + 0.2 * sq(25 * t) + 0.15 * Math.sin(2 * Math.PI * 150 * t) + 0.12 * rand();
  }
  wav('amb/generator.wav', lowpass(x, 700));
}
{
  const x = len(4.0);
  for (let i = 0; i < x.length; i++) x[i] = rand() * 0.5;
  lowpass(x, 600);
  for (let k = 0; k < 18; k++) {
    // distant chatter bursts
    const at = (k * 0.217) % 3.6;
    const b = len(0.35);
    for (let i = 0; i < b.length; i++) b[i] = Math.sin(2 * Math.PI * (180 + 60 * Math.sin(k)) * i / SR) * Math.sin(Math.PI * i / b.length) * 0.08;
    mix(x, b, at);
  }
  wav('amb/street.wav', x);
}
{
  const x = len(1.0);
  for (let i = 0; i < x.length; i++) { const t = i / SR; x[i] = 0.5 * sq(40 * t) * (0.7 + 0.3 * Math.sin(2 * Math.PI * 4 * t)) + 0.1 * rand(); }
  wav('amb/engine.wav', lowpass(x, 400));
}

// ---------- music loops (original, generated) ----------
function groove(bpm, bars, chords, bright, file, calm = false) {
  const beat = 60 / bpm;
  const x = len(bars * 4 * beat);
  for (let b = 0; b < bars; b++) {
    const t0 = b * 4 * beat;
    const root = chords[b % chords.length];
    for (let s = 0; s < 16; s++) {
      const t = t0 + s * beat / 4;
      if (!calm && (s === 0 || s === 6 || s === 10)) mix(x, kick(), t, 0.9);
      if (calm && (s === 0 || s === 8)) mix(x, kick(), t, 0.6);
      if (s === 4 || s === 12) mix(x, clap(), t, calm ? 0.25 : 0.45);
      mix(x, shaker(), t, s % 2 ? 0.25 : 0.4);
      // Bass: root and fifth, syncopated like afrobeat.
      if ([0, 3, 6, 10, 11].includes(s)) mix(x, bassNote(root / 2 * (s === 6 || s === 11 ? 1.5 : 1), beat * 0.45), t, 0.5);
      // Highlife-style guitar: interlocking plucks on the off-beats.
      if ([2, 5, 7, 9, 13, 15].includes(s)) {
        const f = root * 2 * [1, 1.25, 1.5, 2, 1.5, 1.25][[2, 5, 7, 9, 13, 15].indexOf(s)];
        mix(x, pluck(f, beat * 1.2, bright), t, calm ? 0.22 : 0.3);
      }
    }
  }
  wav(file, x);
}
groove(112, 8, [220, 220, 196, 247], 0.6, 'music/day.wav'); // A A G B — bright street groove
groove(88, 8, [165, 147, 165, 196], 0.35, 'music/night.wav', true); // E D E G — night, softer

// ---------- M9–M11 street systems (appended so the sounds above stay byte-identical) ----------
{
  // Task-force siren: a rising and falling two-tone wail.
  const x = len(1.6);
  let ph = 0;
  for (let i = 0; i < x.length; i++) {
    const t = i / SR; ph += (720 + 260 * Math.sin(2 * Math.PI * 1.25 * t)) / SR;
    x[i] = (sq(ph) * 0.5 + saw(ph * 1.01) * 0.3) * 0.35 * env(i, x.length, 0.05, 0.2);
  }
  wav('sfx/siren.wav', lowpass(x, 3000));
}
{
  // Splash: a burst of filtered noise with a falling plop.
  const x = len(0.6);
  for (let i = 0; i < x.length; i++) { const t = i / SR; x[i] = rand() * Math.exp(-t * 7) * 0.6 + Math.sin(2 * Math.PI * (300 - 250 * t) * t) * Math.exp(-t * 12) * 0.4; }
  wav('sfx/splash.wav', lowpass(x, 2200));
}
{
  // Thunder: a long low rumble with a crack at the start.
  const x = len(2.6);
  for (let i = 0; i < x.length; i++) { const t = i / SR; x[i] = rand() * (Math.exp(-t * 1.4) * 0.8 + (t < 0.08 ? 0.6 : 0)); }
  wav('sfx/thunder.wav', lowpass(lowpass(x, 350), 300));
}
{
  // Radio tuning static.
  const x = len(0.4);
  for (let i = 0; i < x.length; i++) { const t = i / SR; x[i] = rand() * 0.4 * (0.6 + 0.4 * Math.sin(2 * Math.PI * 23 * t)) * env(i, x.length, 0.01, 0.1); }
  wav('sfx/static.wav', lowpass(x, 5000));
}
{
  // Sizzle (suya on the grill).
  const x = len(0.9);
  for (let i = 0; i < x.length; i++) x[i] = rand() * (0.25 + 0.15 * Math.sin(i * 0.013)) * env(i, x.length, 0.05, 0.3);
  wav('sfx/sizzle.wav', x);
}
{
  // Punch: a dull thump.
  const x = len(0.25);
  mix(x, kick(0.25), 0, 1);
  mix(x, clap(0.06), 0, 0.5);
  wav('sfx/punch.wav', lowpass(x, 1500));
}
{
  // Rain: steady hiss with drips.
  const x = len(3.0);
  for (let i = 0; i < x.length; i++) x[i] = rand() * 0.45;
  lowpass(x, 2600);
  for (let k = 0; k < 40; k++) mix(x, pluck(1800 + (k * 337) % 1500, 0.05, 0.9), (k * 0.0731) % 2.9, 0.08);
  wav('amb/rain.wav', x);
}
// Radio stations: a brighter highlife loop and a quiet talk-show bed.
groove(124, 8, [262, 220, 175, 196], 0.85, 'music/highlife.wav'); // C A F G — highlife classics
groove(96, 8, [196, 196, 175, 175], 0.25, 'music/talk.wav', true); // a soft studio bed
