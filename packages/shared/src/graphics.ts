/** Graphics settings shared between the client and tooling (proposal F3, decision D-001). */

export type QualityPreset = 'low' | 'medium' | 'high';
export type TextureTier = 'lo' | 'md' | 'hi';
export type ShadowMode = 'none' | 'blob' | 'painted';
export type EffectsLevel = 'off' | 'low' | 'full';
export type FpsCap = 30 | 60 | 0; // 0 = uncapped

export interface GraphicsSettings {
  preset: QualityPreset | 'custom';
  textureTier: TextureTier;
  shadows: ShadowMode;
  effects: EffectsLevel;
  weather: boolean;
  /** Lighting overlay used for NEPA outages and night. */
  nepaOverlay: 'simple' | 'full';
  /** Number of tile chunks streamed around the camera (the 2D "draw distance"). */
  drawDistance: 1 | 2 | 3;
  fpsCap: FpsCap;
  /** Frame rate for NPC sprite-sheet animations. */
  npcAnimFps: 12 | 24;
  maxOnScreenNpcs: number;
  dataSaver: boolean;
  /** Painted stills + text instead of animated cutscenes. */
  lowBandwidthCutscenes: boolean;
  uiScale: number;
  reducedMotion: boolean;
  colourBlindMode: 'off' | 'protan' | 'deutan' | 'tritan';
}

export const PRESETS: Record<QualityPreset, GraphicsSettings> = {
  low: {
    preset: 'low',
    textureTier: 'lo',
    shadows: 'none',
    effects: 'off',
    weather: false,
    nepaOverlay: 'simple',
    drawDistance: 1,
    fpsCap: 30,
    npcAnimFps: 12,
    maxOnScreenNpcs: 12,
    dataSaver: true,
    lowBandwidthCutscenes: true,
    uiScale: 1,
    reducedMotion: false,
    colourBlindMode: 'off',
  },
  medium: {
    preset: 'medium',
    textureTier: 'md',
    shadows: 'blob',
    effects: 'low',
    weather: true,
    nepaOverlay: 'full',
    drawDistance: 2,
    fpsCap: 60,
    npcAnimFps: 12,
    maxOnScreenNpcs: 30,
    dataSaver: false,
    lowBandwidthCutscenes: false,
    uiScale: 1,
    reducedMotion: false,
    colourBlindMode: 'off',
  },
  high: {
    preset: 'high',
    textureTier: 'hi',
    shadows: 'painted',
    effects: 'full',
    weather: true,
    nepaOverlay: 'full',
    drawDistance: 3,
    fpsCap: 60,
    npcAnimFps: 24,
    maxOnScreenNpcs: 60,
    dataSaver: false,
    lowBandwidthCutscenes: false,
    uiScale: 1,
    reducedMotion: false,
    colourBlindMode: 'off',
  },
};

/** Texture scale per tier (atlas resolution multiplier). */
export const TIER_SCALE: Record<TextureTier, number> = { lo: 0.5, md: 1, hi: 2 };
