import Phaser from 'phaser';
import { render } from 'preact';
import { StreetScene } from './game/scenes/StreetScene';
import { App } from './ui/App';
import { fromPreset, graphics, loadSettings, readDeviceSignals, suggestPreset } from './settings/graphics';
import { startDataMeter } from './net/dataMeter';
import { bus } from './game/bus';

startDataMeter();

// Read device signals with a throwaway WebGL context (for the GPU name) before Phaser starts.
const probe = document.createElement('canvas').getContext('webgl');
const signals = readDeviceSignals(probe);
probe?.getExtension('WEBGL_lose_context')?.loseContext();

const suggestion = suggestPreset(signals);
const saved = loadSettings();
graphics.set(saved ?? fromPreset(suggestion.preset, suggestion.dataSaver));

const settings = graphics.get();
const game = new Phaser.Game({
  type: Phaser.WEBGL,
  parent: 'game',
  backgroundColor: '#2b2350',
  scale: { mode: Phaser.Scale.RESIZE, width: window.innerWidth, height: window.innerHeight },
  fps: { target: 60, limit: settings.fpsCap },
  render: { antialias: true, powerPreference: 'low-power' },
  scene: [StreetScene],
  banner: false,
});

// Dev-only handle for automated play-testing; stripped from production builds.
if (import.meta.env.DEV) (window as unknown as { __nsl: unknown }).__nsl = { game, bus, graphics };

render(<App suggestion={suggestion} firstRun={!saved} />, document.getElementById('ui')!);
