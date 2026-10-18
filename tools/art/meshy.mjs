// Meshy API pipeline for the 3D assets (D-020). Reads tools/art/meshy-spec.json and, for each asset:
//   preview (Meshy 6 Lite, remeshed to a phone budget) -> refine (texture) -> download -> slim
//   characters also: rig (gives walking + running) -> slim; one "anim source" character gets
//   the shared action pack (idle, talk, fight...) that every rigged character reuses in Godot.
// Resumable: task ids live in art-src/meshy/state.json, so re-running picks up where it stopped.
// Spend guard: never starts a paid step that would take the run past --budget credits.
//
//   node --env-file=.env tools/art/meshy.mjs [--budget=900] [--only=keke,okada] [--retry] [--status]
//
// The API key stays in the git-ignored .env (MESHY_API_KEY). Raw downloads go to the git-ignored
// art-src/meshy/; the game gets slimmed copies in game/art3d/.
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const SPEC = JSON.parse(fs.readFileSync(path.join(ROOT, "tools/art/meshy-spec.json"), "utf8"));
const RAW = path.join(ROOT, "art-src/meshy");
const OUT = path.join(ROOT, "game/art3d");
const STATE_FILE = path.join(RAW, "state.json");
const API = "https://api.meshy.ai/openapi";
const KEY = process.env.MESHY_API_KEY;
const COST = { preview: 5, refine: 10, rig: 5, action: 3 };
const MAX_LIVE = 8; // Pro allows 10 concurrent tasks; keep two spare for the web app

const args = Object.fromEntries(process.argv.slice(2).map((a) => {
	const [k, v] = a.replace(/^--/, "").split("=");
	return [k, v ?? true];
}));
const BUDGET = Number(args.budget ?? 900);
const ONLY = args.only ? String(args.only).split(",") : null;

if (!KEY) {
	console.error("MESHY_API_KEY is missing from .env");
	process.exit(1);
}
fs.mkdirSync(RAW, { recursive: true });
fs.mkdirSync(path.join(OUT, "chars"), { recursive: true });
const state = fs.existsSync(STATE_FILE) ? JSON.parse(fs.readFileSync(STATE_FILE, "utf8")) : { spent: 0, assets: {} };
const save = () => fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 1));

async function call(method, route, body) {
	for (let attempt = 0; ; attempt++) {
		const r = await fetch(API + route, {
			method,
			headers: { Authorization: "Bearer " + KEY, "Content-Type": "application/json" },
			body: body ? JSON.stringify(body) : undefined,
		});
		if (r.status === 429 && attempt < 8) {
			await sleep(5000 * (attempt + 1));
			continue;
		}
		const text = await r.text();
		if (!r.ok) throw new Error(`${method} ${route} -> ${r.status} ${text.slice(0, 300)}`);
		return text ? JSON.parse(text) : {};
	}
}
const sleep = (ms) => new Promise((res) => setTimeout(res, ms));

async function download(url, file) {
	const r = await fetch(url);
	if (!r.ok) throw new Error(`download ${r.status} for ${path.basename(file)}`);
	const buf = Buffer.from(await r.arrayBuffer());
	if (buf.length < 1000 || buf.toString("ascii", 0, 4) !== "glTF") throw new Error(`not a GLB: ${path.basename(file)}`);
	fs.writeFileSync(file, buf);
	return buf.length;
}

function slim(src, dst, tris, tex) {
	execFileSync(process.execPath, [path.join(ROOT, "tools/art/glb_slim.mjs"), src, dst, String(tris), String(tex)], { stdio: "inherit" });
}

const kindOf = (a) => SPEC.kinds[a.kind];
const live = () => Object.values(state.assets).filter((s) => s.waiting).length;

function canSpend(n) {
	if (state.spent + n > BUDGET) return false;
	state.spent += n;
	save();
	return true;
}

// One step of one asset's state machine. Returns true when the asset is finished.
async function step(a) {
	const s = (state.assets[a.key] ??= {});
	if (s.done) return true;
	if (s.error && !args.retry) return true;
	if (s.error && args.retry) {
		delete s.error;
		for (const k of ["preview", "refine", "rig", "anim"]) if (s[k + "_failed"]) delete s[k], delete s[k + "_failed"];
	}
	const k = kindOf(a);
	const isChar = a.kind === "character";

	// Poll whatever is in flight.
	if (s.waiting) {
		const [ver, kind, id] = s.waiting;
		const t = await call("GET", `/${ver}/${kind}/${id}`);
		if (t.status === "SUCCEEDED") {
			s.waiting = null;
			s[s.stage + "_task"] = t;
		} else if (t.status === "FAILED" || t.status === "CANCELED") {
			s.waiting = null;
			s[s.stage + "_failed"] = true;
			s.error = `${s.stage} ${t.status}: ${JSON.stringify(t.task_error || {}).slice(0, 200)}`;
			state.spent -= s.stage === "preview" ? COST.preview : s.stage === "refine" ? COST.refine : s.stage === "rig" ? COST.rig : 0;
			save();
			console.log(`✗ ${a.key}: ${s.error}`);
			return true;
		} else {
			s.progress = t.progress;
		}
		save();
		return false;
	}
	if (live() >= MAX_LIVE) return false;

	if (!s.preview) {
		if (!canSpend(COST.preview)) return true;
		const prompt = `${a.prompt}, ${isChar ? SPEC.character_style : SPEC.style}`.slice(0, 800);
		const body = { mode: "preview", prompt, ai_model: "meshy-6-lite", should_remesh: true, target_polycount: a.polycount ?? k.polycount, topology: "triangle" };
		if (isChar) body.pose_mode = "a-pose";
		const r = await call("POST", "/v2/text-to-3d", body);
		Object.assign(s, { preview: r.result, stage: "preview", waiting: ["v2", "text-to-3d", r.result] });
		save();
		console.log(`→ ${a.key}: preview ${r.result}`);
		return false;
	}
	if (!s.refine) {
		if (!canSpend(COST.refine)) return true;
		const body = { mode: "refine", preview_task_id: s.preview, enable_pbr: !!k.pbr, texture_prompt: `${a.texture}, ${SPEC.style}`.slice(0, 800) };
		const r = await call("POST", "/v2/text-to-3d", body);
		Object.assign(s, { refine: r.result, stage: "refine", waiting: ["v2", "text-to-3d", r.result] });
		save();
		console.log(`→ ${a.key}: texture ${r.result}`);
		return false;
	}
	if (!s.raw) {
		const raw = path.join(RAW, `${a.key}_raw.glb`);
		const bytes = await download(s.refine_task.model_urls.glb, raw);
		s.raw = path.basename(raw);
		s.credits = (s.credits || 0) + (s.preview_task?.consumed_credits ?? COST.preview) + (s.refine_task.consumed_credits ?? COST.refine);
		save();
		console.log(`↓ ${a.key}: ${(bytes / 1e6).toFixed(1)} MB`);
		if (!isChar) {
			slim(raw, path.join(OUT, `${a.key}.glb`), a.slim ?? k.slim, 1024);
			s.done = true;
			save();
			return true;
		}
	}
	if (isChar && !s.rig) {
		if (!canSpend(COST.rig)) return true;
		const r = await call("POST", "/v1/rigging", { input_task_id: s.refine, height_meters: a.height ?? 1.7 });
		Object.assign(s, { rig: r.result, stage: "rig", waiting: ["v1", "rigging", r.result] });
		save();
		console.log(`→ ${a.key}: rig ${r.result}`);
		return false;
	}
	if (isChar && !s.rigged) {
		const res = s.rig_task.result;
		const walk = path.join(RAW, `${a.key}_walk.glb`);
		await download(res.basic_animations?.walking_glb_url ?? res.rigged_character_glb_url, walk);
		if (res.basic_animations?.running_armature_glb_url) await download(res.basic_animations.running_armature_glb_url, path.join(RAW, `${a.key}_run.glb`));
		slim(walk, path.join(OUT, "chars", `${a.key}.glb`), a.slim ?? k.slim, 1024);
		if (fs.existsSync(path.join(RAW, `${a.key}_run.glb`))) fs.copyFileSync(path.join(RAW, `${a.key}_run.glb`), path.join(OUT, "chars", `${a.key}_run.glb`));
		s.rigged = true;
		save();
		console.log(`✓ ${a.key}: rigged`);
	}
	if (isChar && a.key === SPEC.anim_source && !s.anim) {
		const ids = Object.values(SPEC.anim_actions);
		if (!canSpend(COST.action * ids.length)) {
			s.done = true;
			save();
			return true;
		}
		const r = await call("POST", "/v1/animations", { rig_task_id: s.rig, action_ids: ids });
		Object.assign(s, { anim: r.result, stage: "anim", waiting: ["v1", "animations", r.result] });
		save();
		console.log(`→ ${a.key}: action pack ${r.result}`);
		return false;
	}
	if (isChar && s.anim && !s.anim_file) {
		const f = path.join(RAW, "anim_pack.glb");
		await download(s.anim_task.result.animation_glb_url, f);
		slim(f, path.join(OUT, "chars", "anim_pack.glb"), 1500, 256);
		s.anim_file = true;
		save();
		console.log(`✓ action pack`);
	}
	s.done = true;
	save();
	return true;
}

async function main() {
	const assets = SPEC.assets.filter((a) => !ONLY || ONLY.includes(a.key));
	if (args.status) {
		for (const a of assets) {
			const s = state.assets[a.key] || {};
			console.log(a.key.padEnd(16), s.done ? "done" : s.error ? "ERROR " + s.error : s.stage ? `${s.stage} ${s.progress ?? 0}%` : "-");
		}
		console.log("spent (est.)", state.spent);
		return;
	}
	const bal = await call("GET", "/v1/balance");
	console.log(`balance ${bal.balance}, run budget ${BUDGET}, spent so far ${state.spent}`);
	// Characters first: they need the most steps.
	assets.sort((x, y) => (y.kind === "character") - (x.kind === "character"));
	for (;;) {
		let open = 0;
		for (const a of assets) {
			try {
				if (!(await step(a))) open++;
			} catch (e) {
				const s = (state.assets[a.key] ??= {});
				s.waiting = null;
				s.error = String(e.message || e).slice(0, 300);
				save();
				console.log(`✗ ${a.key}: ${s.error}`);
			}
		}
		if (open === 0) break;
		await sleep(8000);
	}
	const done = assets.filter((a) => state.assets[a.key]?.done && !state.assets[a.key]?.error).length;
	console.log(`finished: ${done}/${assets.length} assets, spent ~${state.spent} credits`);
}

main().catch((e) => {
	console.error(e);
	process.exit(1);
});
