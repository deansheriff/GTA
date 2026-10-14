import { describe, expect, it } from 'vitest';
import { applyDataSaver, fromPreset, suggestPreset } from './graphics';

describe('suggestPreset', () => {
  it('suggests Low and data saver on a 2 GB phone', () => {
    const s = suggestPreset({ deviceMemoryGb: 2, cpuCores: 4, screenShortSide: 360 });
    expect(s.preset).toBe('low');
    expect(s.dataSaver).toBe(true);
  });

  it('never suggests High on a small phone screen', () => {
    const s = suggestPreset({ deviceMemoryGb: 8, cpuCores: 8, screenShortSide: 390 });
    expect(s.preset).toBe('medium');
  });

  it('suggests High on a strong desktop with no signals against it', () => {
    expect(suggestPreset({ deviceMemoryGb: 8, cpuCores: 12, screenShortSide: 1080 }).preset).toBe('high');
  });

  it('drops to Low on an old Mali GPU', () => {
    expect(suggestPreset({ deviceMemoryGb: 4, gpuRenderer: 'Mali-400 MP' }).preset).toBe('low');
  });

  it('turns on data saver for 3G even on a good phone', () => {
    const s = suggestPreset({ deviceMemoryGb: 6, cpuCores: 8, screenShortSide: 400, effectiveType: '3g' });
    expect(s.dataSaver).toBe(true);
    expect(s.reasons.join(' ')).toContain('3g');
  });

  it('respects a slow benchmark', () => {
    expect(suggestPreset({ deviceMemoryGb: 8, cpuCores: 8, screenShortSide: 1000, benchFrameMs: 40 }).preset).toBe('low');
  });
});

describe('data saver', () => {
  it('forces low textures and still cutscenes without touching the fps cap', () => {
    const s = applyDataSaver(fromPreset('high'), true);
    expect(s.textureTier).toBe('lo');
    expect(s.lowBandwidthCutscenes).toBe(true);
    expect(s.fpsCap).toBe(60);
  });
});
