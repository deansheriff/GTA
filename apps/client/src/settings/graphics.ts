import { PRESETS, type GraphicsSettings, type QualityPreset } from '@nsl/shared';

const STORAGE_KEY = 'nsl.graphics.v1';

/** What we can learn about the device without asking the player. Every field may be missing. */
export interface DeviceSignals {
  deviceMemoryGb?: number;
  cpuCores?: number;
  saveData?: boolean;
  effectiveType?: string; // 'slow-2g' | '2g' | '3g' | '4g'
  screenShortSide?: number; // CSS px
  gpuRenderer?: string;
  /** Median frame time in ms from the quick benchmark, if run. */
  benchFrameMs?: number;
}

export interface Suggestion {
  preset: QualityPreset;
  dataSaver: boolean;
  reasons: string[];
}

const WEAK_GPU = /(mali-4|mali-t[67]|adreno \(tm\) [34]\d\d|powervr sgx|swiftshader|llvmpipe)/i;

/**
 * Suggest a preset from device signals. Rules are conservative: when in doubt, go lower.
 * The player always confirms; this only picks the default.
 */
export function suggestPreset(s: DeviceSignals): Suggestion {
  const reasons: string[] = [];
  let score = 2; // 0 = low, 1 = medium, 2 = high

  if (s.deviceMemoryGb !== undefined) {
    if (s.deviceMemoryGb <= 2) { score = Math.min(score, 0); reasons.push(`${s.deviceMemoryGb} GB RAM`); }
    else if (s.deviceMemoryGb <= 4) { score = Math.min(score, 1); reasons.push(`${s.deviceMemoryGb} GB RAM`); }
  }
  if (s.cpuCores !== undefined && s.cpuCores <= 4) {
    score = Math.min(score, 1);
    reasons.push(`${s.cpuCores} CPU cores`);
  }
  if (s.gpuRenderer && WEAK_GPU.test(s.gpuRenderer)) {
    score = 0;
    reasons.push('older graphics chip');
  }
  if (s.screenShortSide !== undefined && s.screenShortSide < 400) {
    // Phones: never default to High; 2x textures are wasted on a small screen.
    score = Math.min(score, 1);
  }
  if (s.benchFrameMs !== undefined) {
    if (s.benchFrameMs > 33) { score = 0; reasons.push('slow frame test'); }
    else if (s.benchFrameMs > 20) { score = Math.min(score, 1); reasons.push('average frame test'); }
  }

  const slowNet = s.effectiveType === 'slow-2g' || s.effectiveType === '2g' || s.effectiveType === '3g';
  const dataSaver = Boolean(s.saveData) || slowNet || score === 0;
  if (s.saveData) reasons.push('your browser asked to save data');
  if (slowNet) reasons.push(`slow network (${s.effectiveType})`);

  const preset: QualityPreset = score === 0 ? 'low' : score === 1 ? 'medium' : 'high';
  return { preset, dataSaver, reasons };
}

export function fromPreset(preset: QualityPreset, dataSaver?: boolean): GraphicsSettings {
  const base = { ...PRESETS[preset] };
  if (dataSaver !== undefined) applyDataSaver(base, dataSaver);
  return base;
}

/** Data saver forces the cheapest network behaviour but leaves frame rate alone. */
export function applyDataSaver(s: GraphicsSettings, on: boolean): GraphicsSettings {
  s.dataSaver = on;
  if (on) {
    s.textureTier = 'lo';
    s.lowBandwidthCutscenes = true;
    s.effects = s.effects === 'full' ? 'low' : s.effects;
  }
  return s;
}

/** Read the device signals that this browser exposes. */
export function readDeviceSignals(gl?: WebGLRenderingContext | WebGL2RenderingContext | null): DeviceSignals {
  const nav = navigator as Navigator & {
    deviceMemory?: number;
    connection?: { saveData?: boolean; effectiveType?: string };
  };
  let gpuRenderer: string | undefined;
  try {
    const ext = gl?.getExtension('WEBGL_debug_renderer_info');
    if (gl && ext) gpuRenderer = String(gl.getParameter(ext.UNMASKED_RENDERER_WEBGL));
  } catch {
    /* some browsers block this; fine */
  }
  return {
    deviceMemoryGb: nav.deviceMemory,
    cpuCores: nav.hardwareConcurrency || undefined,
    saveData: nav.connection?.saveData,
    effectiveType: nav.connection?.effectiveType,
    screenShortSide: Math.min(window.screen.width, window.screen.height),
    gpuRenderer,
  };
}

export function loadSettings(): GraphicsSettings | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<GraphicsSettings>;
    const preset = parsed.preset && parsed.preset !== 'custom' ? parsed.preset : 'medium';
    return { ...PRESETS[preset], ...parsed };
  } catch {
    return null;
  }
}

export function saveSettings(s: GraphicsSettings): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(s));
  } catch {
    /* private mode or blocked storage: settings just won't persist */
  }
}

/** Tiny observable so the Phaser side and the Preact UI share one settings object. */
type Listener = (s: GraphicsSettings) => void;
let current: GraphicsSettings = PRESETS.medium;
const listeners = new Set<Listener>();

export const graphics = {
  get: () => current,
  set(next: GraphicsSettings) {
    current = next;
    saveSettings(next);
    listeners.forEach((l) => l(next));
  },
  subscribe(l: Listener) {
    listeners.add(l);
    return () => listeners.delete(l);
  },
};
