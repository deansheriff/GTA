/**
 * Placeholder palette: warm, saturated, readable on dim phone screens (proposal §4.1).
 * Danfo yellow and NEPA night-blue are the signature colours.
 */
export const PAL = {
  danfo: '#f2b705',
  danfoDark: '#b98600',
  nepaNight: '#2b2350',
  earth: '#b86b42',
  earthDry: '#c98a55',
  grass: '#6f9a3a',
  grassDark: '#4f7a2a',
  asphalt: '#4d4852',
  roadLine: '#e9dfb8',
  interlock: '#c7a77a',
  concrete: '#a39d92',
  gutterWater: '#3d4a3a',
  zinc: '#9aa3a8',
  rust: '#9c5a34',
  walls: ['#e8c07a', '#9cc5a1', '#e39a7a', '#a9b8e0', '#f0e2c0', '#d9a5c6'],
  window: '#2e3f5c',
  skin: ['#5a3825', '#6e4430', '#7d4f36', '#8a5a3c', '#4a2e20'],
  shirts: ['#c0392b', '#2e86c1', '#27ae60', '#f39c12', '#8e44ad', '#16a085', '#d35400', '#ecf0f1'],
  ankara: ['#e67e22', '#1abc9c', '#9b59b6', '#e74c3c'],
  trousers: ['#2c3e50', '#34495e', '#5d4037', '#1b2631', '#7f8c8d'],
} as const;

/** Fictional signage only: no real brands (Story Bible §5). */
export const SIGNS = [
  'AUNTY BOSS KITCHEN',
  'KONFAM POS',
  'GIDI BARBING SALON',
  '9BARS RECHARGE',
  'NO CONDITION IS PERMANENT',
  'MIRACLE FM 99.9',
  'TAP-TAP POS',
  'GOD\'S TIME PHONE REPAIRS',
] as const;
