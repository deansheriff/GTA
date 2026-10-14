class_name DeviceProfile
extends RefCounted
## Graphics presets and the first-launch suggestion (proposal F3).
## Pure functions so they can be unit-tested headless.

const PRESETS := {
	"low": {
		"preset": "low", "texture_tier": "lo", "shadows": "none", "effects": "off", "weather": false,
		"lighting": "simple", "draw_distance": 1, "fps_cap": 30, "npc_anim_fps": 8, "max_npcs": 12,
		"data_saver": true, "still_cutscenes": true, "ui_scale": 1.0, "reduced_motion": false,
	},
	"medium": {
		"preset": "medium", "texture_tier": "md", "shadows": "blob", "effects": "low", "weather": true,
		"lighting": "full", "draw_distance": 2, "fps_cap": 60, "npc_anim_fps": 10, "max_npcs": 30,
		"data_saver": false, "still_cutscenes": false, "ui_scale": 1.0, "reduced_motion": false,
	},
	"high": {
		"preset": "high", "texture_tier": "hi", "shadows": "painted", "effects": "full", "weather": true,
		"lighting": "full", "draw_distance": 3, "fps_cap": 60, "npc_anim_fps": 12, "max_npcs": 60,
		"data_saver": false, "still_cutscenes": false, "ui_scale": 1.0, "reduced_motion": false,
	},
}

const WEAK_GPU_PATTERNS := ["mali-4", "mali-t6", "mali-t7", "adreno (tm) 3", "adreno (tm) 4", "powervr sge", "powervr sgx", "llvmpipe", "swiftshader"]


## signals: { ram_gb, cores, gpu, short_side_inches, is_mobile, bench_ms (optional) }
## Returns { preset: String, data_saver: bool, reasons: Array[String] }
static func suggest(signals: Dictionary) -> Dictionary:
	var score := 2 # 0 low, 1 medium, 2 high
	var reasons: Array[String] = []
	var ram: float = signals.get("ram_gb", -1.0)
	if ram > 0.0:
		if ram <= 3.0:
			score = 0
			reasons.append("%.0f GB RAM" % ram)
		elif ram <= 4.5:
			score = mini(score, 1)
			reasons.append("%.0f GB RAM" % ram)
	var cores: int = signals.get("cores", -1)
	if cores > 0 and cores <= 4:
		score = mini(score, 1)
		reasons.append("%d CPU cores" % cores)
	var gpu: String = String(signals.get("gpu", "")).to_lower()
	for pat in WEAK_GPU_PATTERNS:
		if gpu.contains(pat):
			score = 0
			reasons.append("older graphics chip")
			break
	if signals.get("is_mobile", false):
		# Phones never default to High: 2x textures cost memory and battery for little gain.
		score = mini(score, 1)
	var bench: float = signals.get("bench_ms", -1.0)
	if bench > 0.0:
		if bench > 33.0:
			score = 0
			reasons.append("slow frame test")
		elif bench > 20.0:
			score = mini(score, 1)
			reasons.append("average frame test")
	var preset: String = ["low", "medium", "high"][score]
	return { "preset": preset, "data_saver": score == 0, "reasons": reasons }


static func from_preset(preset: String, data_saver: Variant = null) -> Dictionary:
	var s: Dictionary = (PRESETS.get(preset, PRESETS["medium"]) as Dictionary).duplicate()
	if data_saver != null:
		apply_data_saver(s, bool(data_saver))
	return s


## Data saver forces the cheapest network behaviour but leaves the frame-rate cap alone.
static func apply_data_saver(s: Dictionary, on: bool) -> Dictionary:
	s["data_saver"] = on
	if on:
		s["texture_tier"] = "lo"
		s["still_cutscenes"] = true
		if s.get("effects") == "full":
			s["effects"] = "low"
	return s


## Read what this device tells us about itself.
static func read_signals() -> Dictionary:
	var mem := OS.get_memory_info()
	var physical: int = mem.get("physical", -1)
	var screen := DisplayServer.screen_get_size()
	var dpi := maxi(DisplayServer.screen_get_dpi(), 1)
	return {
		"ram_gb": float(physical) / 1073741824.0 if physical > 0 else -1.0,
		"cores": OS.get_processor_count(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"short_side_inches": float(mini(screen.x, screen.y)) / float(dpi),
		"is_mobile": OS.has_feature("mobile"),
	}
