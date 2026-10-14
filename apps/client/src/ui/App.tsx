import { useEffect, useRef, useState } from 'preact/hooks';
import { formatBytes, type GraphicsSettings, type QualityPreset } from '@nsl/shared';
import { bus, type GameState } from '../game/bus';
import { applyDataSaver, fromPreset, graphics, type Suggestion } from '../settings/graphics';
import { dataMeter } from '../net/dataMeter';
import './ui.css';

export function App({ suggestion, firstRun }: { suggestion: Suggestion; firstRun: boolean }) {
  const [state, setState] = useState<GameState>({ mode: 'walking', nearDanfo: false, night: false, nepaOn: true, fps: 0 });
  const [settings, setSettings] = useState<GraphicsSettings>(graphics.get());
  const [bytes, setBytes] = useState(0);
  const [showSettings, setShowSettings] = useState(false);
  const [showWelcome, setShowWelcome] = useState(firstRun);
  const [toast, setToast] = useState<string | null>(null);
  const touch = typeof matchMedia === 'function' && matchMedia('(pointer: coarse)').matches;

  useEffect(() => {
    const offs = [
      bus.on('state', (s) => { setState(s); if (s.toast) setToast(s.toast); }),
      graphics.subscribe(setSettings),
      dataMeter.subscribe(setBytes),
    ];
    return () => offs.forEach((o) => o());
  }, []);

  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 2600);
    return () => clearTimeout(t);
  }, [toast]);

  return (
    <div class="nsl-ui" style={{ fontSize: `${settings.uiScale * 100}%` }}>
      <header class="hud">
        <div class="hud-title">
          <strong>Naija Street Life</strong>
          <span class="tag">M0 style test · placeholder art</span>
        </div>
        <div class="hud-stats" aria-live="polite">
          <span title="Data used this session">📶 {formatBytes(bytes)}</span>
          <span title="Frames per second">{state.fps} fps</span>
          <span>{state.night ? '🌙' : '☀️'} {state.nepaOn ? '💡 Light dey' : '🕯️ No light'}</span>
        </div>
      </header>

      <nav class="hud-actions">
        <button onClick={() => setShowSettings(true)} aria-label="Graphics settings">⚙️</button>
        <button onClick={() => bus.emit('toggleNight', undefined)} aria-label="Toggle night">{state.night ? '☀️' : '🌙'}</button>
        <button onClick={() => bus.emit('toggleNepa', undefined)} aria-label="Toggle NEPA power">{state.nepaOn ? '🕯️' : '💡'}</button>
      </nav>

      {(state.nearDanfo || state.mode === 'driving') && (
        <button class="enter-btn" onClick={() => bus.emit('enterExit', undefined)}>
          {state.mode === 'driving' ? 'Comot from danfo' : 'Enter Baba God Dey 🚐'} {!touch && <kbd>E</kbd>}
        </button>
      )}

      {touch && <Joystick />}
      {!touch && <p class="hint">Click to walk · WASD/arrows to move or drive · E to enter the danfo · wheel to zoom</p>}

      {toast && <div class={`toast ${toast.startsWith('UP NEPA') ? 'toast-big' : ''}`} role="status">{toast}</div>}

      {showWelcome && <Welcome suggestion={suggestion} onClose={() => setShowWelcome(false)} onCustomise={() => { setShowWelcome(false); setShowSettings(true); }} />}
      {showSettings && <SettingsPanel settings={settings} suggestion={suggestion} onClose={() => setShowSettings(false)} />}
    </div>
  );
}

function Welcome({ suggestion, onClose, onCustomise }: { suggestion: Suggestion; onClose: () => void; onCustomise: () => void }) {
  return (
    <div class="modal" role="dialog" aria-labelledby="welcome-title">
      <div class="card">
        <h2 id="welcome-title">We set up graphics for your phone</h2>
        <p>
          <strong>{label(suggestion.preset)}</strong>
          {suggestion.dataSaver && ' + Data saver'}
        </p>
        {suggestion.reasons.length > 0 && <p class="muted">Because: {suggestion.reasons.join(', ')}.</p>}
        <div class="row">
          <button class="primary" onClick={onClose}>Use this</button>
          <button onClick={onCustomise}>Choose myself</button>
        </div>
      </div>
    </div>
  );
}

const label = (p: QualityPreset | 'custom'): string => ({ low: 'Low', medium: 'Medium', high: 'High', custom: 'Custom' })[p];

function SettingsPanel({ settings, suggestion, onClose }: { settings: GraphicsSettings; suggestion: Suggestion; onClose: () => void }) {
  const set = (patch: Partial<GraphicsSettings>) => graphics.set({ ...settings, ...patch, preset: 'custom' });
  const pick = (p: QualityPreset) => graphics.set(fromPreset(p, settings.dataSaver));
  return (
    <div class="modal" role="dialog" aria-labelledby="gfx-title">
      <div class="card settings">
        <div class="row between">
          <h2 id="gfx-title">Graphics</h2>
          <button onClick={onClose} aria-label="Close">✕</button>
        </div>
        <fieldset>
          <legend>Quality</legend>
          <div class="seg">
            {(['low', 'medium', 'high'] as const).map((p) => (
              <button key={p} class={settings.preset === p ? 'on' : ''} onClick={() => pick(p)}>
                {label(p)}{suggestion.preset === p && ' ★'}
              </button>
            ))}
          </div>
          <p class="muted">★ suggested for this device{settings.preset === 'custom' && ' · you are on Custom'}</p>
        </fieldset>

        <Toggle label="Data saver" hint="Low textures, still cutscenes, no prefetch" value={settings.dataSaver}
          onChange={(v) => graphics.set(applyDataSaver({ ...settings, preset: 'custom' }, v))} />
        <Choice label="Texture quality" value={settings.textureTier} options={[['lo', 'Low'], ['md', 'Medium'], ['hi', 'High']]} onChange={(v) => set({ textureTier: v })} />
        <Choice label="Shadows" value={settings.shadows} options={[['none', 'Off'], ['blob', 'Simple'], ['painted', 'Painted']]} onChange={(v) => set({ shadows: v })} />
        <Choice label="Effects" value={settings.effects} options={[['off', 'Off'], ['low', 'Low'], ['full', 'Full']]} onChange={(v) => set({ effects: v })} />
        <Choice label="Draw distance" value={String(settings.drawDistance)} options={[['1', 'Near'], ['2', 'Medium'], ['3', 'Far']]} onChange={(v) => set({ drawDistance: Number(v) as 1 | 2 | 3 })} />
        <Choice label="Frame-rate cap" value={String(settings.fpsCap)} options={[['30', '30'], ['60', '60'], ['0', 'No cap']]} onChange={(v) => set({ fpsCap: Number(v) as 30 | 60 | 0 })} />
        <Choice label="Night & NEPA lighting" value={settings.nepaOverlay} options={[['simple', 'Simple'], ['full', 'Full']]} onChange={(v) => set({ nepaOverlay: v })} />
        <Toggle label="Weather" value={settings.weather} onChange={(v) => set({ weather: v })} />
        <Toggle label="Still cutscenes (low data)" value={settings.lowBandwidthCutscenes} onChange={(v) => set({ lowBandwidthCutscenes: v })} />
        <Toggle label="Reduce motion (no screen shake)" value={settings.reducedMotion} onChange={(v) => set({ reducedMotion: v })} />
        <Choice label="Text size" value={String(settings.uiScale)} options={[['1', 'Normal'], ['1.2', 'Large'], ['1.4', 'Larger']]} onChange={(v) => set({ uiScale: Number(v) })} />
        <p class="muted">Shadows, weather and colour-blind modes switch on with the real art in M1.</p>
      </div>
    </div>
  );
}

function Toggle({ label, hint, value, onChange }: { label: string; hint?: string; value: boolean; onChange: (v: boolean) => void }) {
  return (
    <label class="setting">
      <span>{label}{hint && <small>{hint}</small>}</span>
      <input type="checkbox" checked={value} onChange={(e) => onChange((e.target as HTMLInputElement).checked)} />
    </label>
  );
}

function Choice<T extends string>({ label, value, options, onChange }: { label: string; value: T; options: Array<[T, string]>; onChange: (v: T) => void }) {
  return (
    <div class="setting">
      <span>{label}</span>
      <div class="seg small" role="radiogroup" aria-label={label}>
        {options.map(([v, l]) => (
          <button key={v} role="radio" aria-checked={value === v} class={value === v ? 'on' : ''} onClick={() => onChange(v)}>{l}</button>
        ))}
      </div>
    </div>
  );
}

/** Thumb-stick for phones. Emits a screen-space vector on the bus. */
function Joystick() {
  const base = useRef<HTMLDivElement>(null);
  const [knob, setKnob] = useState({ x: 0, y: 0 });
  const R = 48;
  const move = (e: PointerEvent) => {
    const rect = base.current!.getBoundingClientRect();
    let x = e.clientX - (rect.left + rect.width / 2), y = e.clientY - (rect.top + rect.height / 2);
    const l = Math.hypot(x, y);
    if (l > R) { x = (x / l) * R; y = (y / l) * R; }
    setKnob({ x, y });
    bus.emit('joystick', { x: x / R, y: y / R });
  };
  const end = () => { setKnob({ x: 0, y: 0 }); bus.emit('joystick', { x: 0, y: 0 }); };
  return (
    <div class="joystick" ref={base}
      onPointerDown={(e) => { (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId); move(e as unknown as PointerEvent); }}
      onPointerMove={(e) => e.buttons && move(e as unknown as PointerEvent)}
      onPointerUp={end} onPointerCancel={end} aria-label="Move">
      <div class="knob" style={{ transform: `translate(${knob.x}px, ${knob.y}px)` }} />
    </div>
  );
}
