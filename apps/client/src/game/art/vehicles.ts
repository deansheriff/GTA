import { PAL } from './palette';
import { blobShadow, boundsOf, inkPath, makeCanvas, paintPath, poly, shade, type Ctx } from './paint';

/**
 * Renders a box-built vehicle from any of 8 headings. This is the code stand-in for the
 * "model once in Blender, render 8 directions, paint over" pipeline in proposal §4.2.
 */
export interface VehicleSpec {
  length: number; // px at 1x, along heading
  width: number;
  height: number; // body height
  body: string;
  stripe?: string;
  windowTint: string;
  backText?: string;
  sideText?: string;
  seed: number;
}

export const DANFO: VehicleSpec = {
  length: 96,
  width: 46,
  height: 40,
  body: PAL.danfo,
  stripe: '#1a1a1a',
  windowTint: '#9fd3e6',
  backText: 'BABA GOD DEY',
  sideText: 'NO CONDITION IS PERMANENT',
  seed: 77,
};

type V3 = [number, number, number];
const K = Math.SQRT1_2;

/** Draw the vehicle facing direction index 0..7 (0 = +x tile axis, screen SE). */
export function drawVehicle(spec: VehicleSpec, dir: number, s: number, damage = 0): { canvas: HTMLCanvasElement; originX: number; originY: number } {
  const size = (spec.length + spec.width) * s + 20 * s;
  const W = size, H = size * 0.6 + spec.height * s + 12 * s;
  const { c, g } = makeCanvas(W, H);
  const ox = W / 2, oy = H - size * 0.3 - 6 * s;
  const th = (dir * Math.PI) / 4;
  const cos = Math.cos(th), sin = Math.sin(th);
  const L = spec.length / 2, Wd = spec.width / 2;

  const proj = ([x, y, z]: V3): [number, number] => {
    const wx = x * cos - y * sin;
    const wy = x * sin + y * cos;
    return [ox + (wx - wy) * K * s, oy + (wx + wy) * K * 0.5 * s - z * s];
  };
  const normalVisible = (nx: number, ny: number) => {
    const wx = nx * cos - ny * sin;
    const wy = nx * sin + ny * cos;
    return wx + wy > 0.01;
  };

  blobShadow(g, ox, oy, (spec.length * 0.55) * s, (spec.length * 0.3) * s, 0.4);

  const h = spec.height;
  // Faces as [bottom-left, bottom-right, top-right, top-left] seen from outside.
  const faces: Array<{ n: [number, number]; pts: V3[]; kind: 'side' | 'front' | 'back' }> = [
    { n: [0, 1], kind: 'side', pts: [[-L, Wd, 0], [L, Wd, 0], [L, Wd, h], [-L, Wd, h]] },
    { n: [0, -1], kind: 'side', pts: [[L, -Wd, 0], [-L, -Wd, 0], [-L, -Wd, h], [L, -Wd, h]] },
    { n: [1, 0], kind: 'front', pts: [[L, Wd, 0], [L, -Wd, 0], [L, -Wd, h], [L, Wd, h]] },
    { n: [-1, 0], kind: 'back', pts: [[-L, -Wd, 0], [-L, Wd, 0], [-L, Wd, h], [-L, -Wd, h]] },
  ];

  // Wheels first (they sit under the body).
  for (const [wx, wy] of [[L * 0.62, Wd], [-L * 0.62, Wd], [L * 0.62, -Wd], [-L * 0.62, -Wd]] as Array<[number, number]>) {
    const [px, py] = proj([wx, wy, 6]);
    g.fillStyle = '#1d1d1d';
    g.beginPath(); g.ellipse(px, py, 8 * s, 6 * s, 0, 0, Math.PI * 2); g.fill();
  }

  for (const f of faces) {
    if (!normalVisible(f.n[0], f.n[1])) continue;
    const pts2 = f.pts.map(proj);
    const tone = f.kind === 'side' ? (f.n[1] > 0 ? 0 : -0.12) : f.kind === 'front' ? 0.05 : -0.08;
    paintPath(g, poly(pts2), shade(spec.body, tone), spec.seed + f.n[0] * 3 + f.n[1] * 5, { bounds: boundsOf(pts2), spread: 0.08, dabs: 30 });
    const at = (u: number, v: number): [number, number] => {
      const [bl, br, , tl] = f.pts as [V3, V3, V3, V3];
      return proj([bl[0] + (br[0] - bl[0]) * u + (tl[0] - bl[0]) * v, bl[1] + (br[1] - bl[1]) * u + (tl[1] - bl[1]) * v, bl[2] + (tl[2] - bl[2]) * v]);
    };
    const quad = (u0: number, u1: number, v0: number, v1: number) => poly([at(u0, v0), at(u1, v0), at(u1, v1), at(u0, v1)]);

    // The black danfo band.
    if (spec.stripe) { g.fillStyle = spec.stripe; g.fill(quad(0, 1, 0.38, 0.48)); }

    if (f.kind === 'side') {
      for (let k = 0; k < 4; k++) {
        const u0 = 0.08 + k * 0.22;
        g.fillStyle = spec.windowTint;
        g.fill(quad(u0, u0 + 0.18, 0.58, 0.88));
      }
      if (spec.sideText) mapText(g, at(0.06, 0.34), at(0.94, 0.34), at(0.06, 0.2), spec.sideText, '#1a1a1a');
    } else if (f.kind === 'front') {
      g.fillStyle = shade(spec.windowTint, -0.1);
      g.fill(quad(0.1, 0.9, 0.55, 0.92));
      g.fillStyle = '#fff3b0';
      g.fill(quad(0.06, 0.2, 0.2, 0.3)); g.fill(quad(0.8, 0.94, 0.2, 0.3));
    } else {
      g.fillStyle = spec.windowTint;
      g.fill(quad(0.15, 0.85, 0.6, 0.88));
      if (spec.backText) mapText(g, at(0.05, 0.34), at(0.95, 0.34), at(0.05, 0.18), spec.backText, '#1a1a1a');
    }
    inkPath(g, poly(pts2), 1.2 * s);
  }

  // Roof with a luggage rack.
  const roof = ([[L, Wd, h], [L, -Wd, h], [-L, -Wd, h], [-L, Wd, h]] as V3[]).map(proj);
  paintPath(g, poly(roof), shade(spec.body, 0.12), spec.seed + 99, { bounds: boundsOf(roof), dabs: 20 });
  inkPath(g, poly(roof), 1.2 * s);
  g.strokeStyle = 'rgba(40,40,40,0.6)';
  g.lineWidth = 1.5 * s;
  for (const t of [-0.5, 0, 0.5]) {
    const a = proj([L * t, Wd * 0.8, h + 4]), b = proj([L * t, -Wd * 0.8, h + 4]);
    g.beginPath(); g.moveTo(...a); g.lineTo(...b); g.stroke();
  }

  // Dents and tape for damage states.
  if (damage > 0) {
    g.fillStyle = 'rgba(120,80,40,0.5)';
    for (let i = 0; i < damage * 4; i++) {
      const [px, py] = proj([(-0.8 + i * 0.4) * L, Wd, h * 0.3]);
      g.beginPath(); g.ellipse(px, py, 5 * s, 3 * s, 0.3, 0, Math.PI * 2); g.fill();
    }
  }
  return { canvas: c, originX: ox / W, originY: oy / H };
}

/** Draw text onto an arbitrary quad (text box top-left, top-right, bottom-left in canvas px). */
function mapText(g: Ctx, tl: [number, number], tr: [number, number], bl: [number, number], text: string, colour: string) {
  const bw = 240, bh = 24;
  g.save();
  g.setTransform((tr[0] - tl[0]) / bw, (tr[1] - tl[1]) / bw, (bl[0] - tl[0]) / bh, (bl[1] - tl[1]) / bh, tl[0], tl[1]);
  // The face basis can be mirrored; flip back so text always reads left to right.
  const det = (tr[0] - tl[0]) * (bl[1] - tl[1]) - (tr[1] - tl[1]) * (bl[0] - tl[0]);
  if (det < 0) { g.translate(bw, 0); g.scale(-1, 1); }
  g.fillStyle = colour;
  g.font = 'bold 18px system-ui, sans-serif';
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  g.fillText(text, bw / 2, bh / 2, bw - 6);
  g.restore();
}
