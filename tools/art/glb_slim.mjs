#!/usr/bin/env node
/**
 * Makes a Meshy GLB phone-friendly for the 3D prototype (game/proto3d):
 * weld → simplify to a target triangle count (meshoptimizer) → resize every texture.
 *   node tools/art/glb_slim.mjs <in.glb> <out.glb> [targetTriangles=12000] [maxTexture=1024]
 * Meshy free-plan models are CC BY 4.0: the game credits "3D models made with Meshy (meshy.ai)".
 */
import { NodeIO } from '@gltf-transform/core';
import { weld, simplify, dedup, prune } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';
import sharp from 'sharp';

const [inp, out, target = '12000', maxTex = '1024'] = process.argv.slice(2);
if (!inp || !out) { console.error('usage: glb_slim.mjs in.glb out.glb [triangles] [maxTexture]'); process.exit(1); }
const io = new NodeIO();
const doc = await io.read(inp);
const tris = () => doc.getRoot().listMeshes().reduce((n, m) => n + m.listPrimitives().reduce((k, p) => k + (p.getIndices()?.getCount() ?? 0) / 3, 0), 0);
const before = tris();
await MeshoptSimplifier.ready;
await doc.transform(weld(), dedup());
const ratio = Math.min(1, Number(target) / Math.max(1, tris()));
if (ratio < 1) await doc.transform(simplify({ simplifier: MeshoptSimplifier, ratio, error: 0.01 }));
for (const tex of doc.getRoot().listTextures()) {
  const img = tex.getImage();
  if (!img) continue;
  const meta = await sharp(img).metadata();
  if ((meta.width ?? 0) <= Number(maxTex)) continue;
  const resized = await sharp(img).resize(Number(maxTex), Number(maxTex), { fit: 'inside' }).jpeg({ quality: 85 }).toBuffer();
  tex.setImage(resized).setMimeType('image/jpeg');
}
await doc.transform(prune());
await io.write(out, doc);
console.log(`${out}: ${Math.round(before)} → ${Math.round(tris())} triangles`);
