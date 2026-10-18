// Downloads the free assets listed in tools/art/free-assets.json from Poly Pizza (D-024):
// checks each model page's licence (CC0 or CC-BY only), downloads the GLB into the git-ignored
// art-src/free/, checks it is a real glTF binary, slims it into game/art3d/free/ and writes the
// attribution table docs/art/FREE_ASSETS.md.   node tools/art/free_assets.mjs [--only=a,b]
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const SPEC = JSON.parse(fs.readFileSync(path.join(ROOT, "tools/art/free-assets.json"), "utf8"));
const RAW = path.join(ROOT, "art-src/free");
const OUT = path.join(ROOT, "game/art3d/free");
const ALLOWED = /^(Public Domain \(CC0\)|CC0 1\.0|CC-BY 3\.0|Creative Commons Attribution)/;
const only = (process.argv.find((a) => a.startsWith("--only=")) ?? "").slice(7).split(",").filter(Boolean);
fs.mkdirSync(RAW, { recursive: true });
fs.mkdirSync(OUT, { recursive: true });

const rows = [];
for (const a of SPEC.assets) {
  if (only.length && !only.includes(a.key)) continue;
  const page = `https://poly.pizza/m/${a.id}`;
  const html = await (await fetch(page)).text();
  const glb = html.match(/static\.poly\.pizza\/[a-f0-9-]+\.glb/);
  const lic = html.match(/Public Domain \(CC0\)|CC0 1\.0|CC-BY 3\.0|Creative Commons Attribution[^"<]*/);
  const title = html.match(/<title[^>]*>([^<]*?) - Free 3D Model By ([^<]*?) - Poly Pizza<\/title>/);
  if (!glb || !lic || !ALLOWED.test(lic[0])) {
    console.log(`✗ ${a.key}: no allowed licence or file on ${page}`);
    continue;
  }
  const raw = path.join(RAW, `${a.key}.glb`);
  const buf = Buffer.from(await (await fetch(`https://${glb[0]}`)).arrayBuffer());
  if (buf.length < 500 || buf.toString("ascii", 0, 4) !== "glTF") {
    console.log(`✗ ${a.key}: not a GLB`);
    continue;
  }
  fs.writeFileSync(raw, buf);
  execFileSync(process.execPath, [path.join(ROOT, "tools/art/glb_slim.mjs"), raw, path.join(OUT, `${a.key}.glb`), String(a.tris ?? 4000), "512"], { stdio: "inherit" });
  const cc0 = /CC0/.test(lic[0]);
  rows.push({ key: a.key, name: title ? title[1] : a.key, author: title ? title[2] : "?", licence: cc0 ? "CC0" : "CC-BY 3.0", page, use: a.use });
  console.log(`✓ ${a.key}: ${rows.at(-1).name} by ${rows.at(-1).author} (${rows.at(-1).licence})`);
}

// Merge with any rows already recorded, then write the table.
const doc = path.join(ROOT, "docs/art/FREE_ASSETS.md");
const prev = fs.existsSync(doc) ? fs.readFileSync(doc, "utf8") : "";
const keep = prev.split("\n").filter((l) => l.startsWith("| `") && !rows.some((r) => l.startsWith(`| \`${r.key}\``)));
const lines = [
  "# Free 3D assets (D-024)",
  "",
  "Downloaded with `tools/art/free_assets.mjs` from Poly Pizza. CC0 needs no credit. CC-BY 3.0 needs",
  "the credit below, which the game's credits screen repeats.",
  "",
  "| File | Model | Author | Licence | Source | Used for |",
  "|---|---|---|---|---|---|",
  ...keep,
  ...rows.map((r) => `| \`${r.key}\` | ${r.name} | ${r.author} | ${r.licence} | ${r.page} | ${r.use} |`),
  "",
];
fs.writeFileSync(doc, lines.join("\n"));
console.log(`${rows.length} assets; table: docs/art/FREE_ASSETS.md`);
