class_name Models3D
extends RefCounted
## The 3D model library (D-020): the Meshy GLBs in res://art3d/, which game things they stand for,
## and helpers to fit them to a size. Every lookup falls back gracefully (null) when a model hasn't
## been made yet, so the 3D world always builds.

const ART := "res://art3d/"
const CHARS := "res://art3d/chars/"

## Map building art -> model keys (several = pick by the building's seed for variety).
const BUILDINGS := {
	"canteen": ["canteen"],
	"pos-shop": ["pos_shop"],
	"provision-store": ["provision_store"],
	"bungalow": ["bungalow", "island_cottage"],
	"two-storey": ["shop", "apartment"],
	"island-cottage": ["island_cottage", "bungalow"],
	"fisher-hut": ["fisher_hut"],
	"beach-bar": ["beach_bar"],
}
## Landmark kinds and particular landmarks with a model of their own.
const LANDMARKS := {
	"park": "motor_park", "market": "market", "station": "station",
	"yaba-church": "church", "northvale-embassy": "office_tower", "miracle-fm": "office_tower",
	"agbado-ketu-council": "office_tower",
}
## District flavour: rich districts get duplexes and towers, crowded ones get shacks.
const DISTRICT_SWAP := {
	"lekki": { "bungalow": "mansion", "two-storey": "mansion" },
	"ikoyi": { "two-storey": "office_tower", "bungalow": "mansion" },
	"vi": { "two-storey": "office_tower" },
	"mushin": { "bungalow": "shack" },
	"agbado-ketu": { "bungalow": "shack" },
}

## Map prop kind -> [model key, height in metres].
const PROPS := {
	"palm": ["palm", 8.5], "palm-cluster": ["palm", 7.5], "mango": ["mango", 6.5],
	"pole": ["pole", 8.0], "transformer": ["transformer", 3.2], "generator": ["generator", 0.9],
	"kiosk": ["kiosk", 2.6], "tyres": ["tyres", 1.2], "drum-chairs": ["drum_chairs", 0.9],
	"orange-tray": ["orange_tray", 1.1], "canoe": ["canoe", 0.9], "nets": ["nets", 2.2],
	"fish-baskets": ["fish_baskets", 0.7], "coconut-cart": ["coconut_cart", 1.3],
	"umbrella": ["umbrella", 2.6], "beach-umbrella": ["umbrella", 2.6],
}

## Vehicle kinds: model key, length x width (m), top speed (m/s), acceleration, turn rate.
const VEHICLES := {
	"danfo": { "model": "danfo", "size": Vector2(4.8, 2.2), "top": 16.0, "accel": 7.0, "turn": 1.7 },
	"keke": { "model": "keke", "size": Vector2(2.7, 1.4), "top": 12.0, "accel": 6.0, "turn": 2.4 },
	"okada": { "model": "okada", "size": Vector2(2.0, 0.8), "top": 20.0, "accel": 10.0, "turn": 2.8 },
	"car": { "model": "car", "size": Vector2(4.4, 1.8), "top": 19.0, "accel": 8.0, "turn": 2.0 },
	"taxi": { "model": "taxi", "size": Vector2(4.4, 1.8), "top": 18.0, "accel": 8.0, "turn": 2.0 },
	"suv": { "model": "suv", "size": Vector2(4.8, 2.0), "top": 21.0, "accel": 9.0, "turn": 1.9 },
	"bus": { "model": "bus", "size": Vector2(11.0, 2.5), "top": 13.0, "accel": 4.0, "turn": 1.1 },
	"tanker": { "model": "tanker", "size": Vector2(9.0, 2.5), "top": 12.0, "accel": 3.5, "turn": 1.1 },
	"truck": { "model": "truck", "size": Vector2(7.5, 2.4), "top": 13.0, "accel": 4.0, "turn": 1.2 },
	"pickup": { "model": "pickup", "size": Vector2(5.0, 1.9), "top": 19.0, "accel": 8.0, "turn": 1.9 },
	"van": { "model": "van", "size": Vector2(4.8, 1.9), "top": 16.0, "accel": 6.0, "turn": 1.8 },
}
## How often each kind turns up in traffic (Lagos: danfos, kekes and okadas everywhere).
const TRAFFIC_MIX := ["danfo", "danfo", "danfo", "keke", "keke", "okada", "okada", "car", "car", "taxi", "suv", "bus", "truck", "tanker", "pickup", "van"]

## Townspeople models (rigged): key -> height.
const PEOPLE := ["walker", "market_woman", "okada_rider", "agbero", "businessman", "young_woman", "elder", "aunty_boss", "chief", "marshal", "taskforce"]

var _scenes := {}
var _anim_lib: AnimationLibrary
var _anim_checked := false


func scene(key: String, dir := ART) -> PackedScene:
	var path := dir + key + ".glb"
	if _scenes.has(path):
		return _scenes[path]
	var ps: PackedScene = load(path) if ResourceLoader.exists(path) else null
	_scenes[path] = ps
	return ps


func has(key: String, dir := ART) -> bool:
	return scene(key, dir) != null


## A fresh instance of a model, or null.
func make(key: String, dir := ART) -> Node3D:
	var ps := scene(key, dir)
	return ps.instantiate() as Node3D if ps else null


func building_key(art: String, seed: int, district: String, landmark := "") -> String:
	if LANDMARKS.has(landmark) and has(LANDMARKS[landmark]):
		return LANDMARKS[landmark]
	var swap: Dictionary = DISTRICT_SWAP.get(district, {})
	if swap.has(art) and seed % 3 != 0 and has(swap[art]):
		return swap[art]
	var opts: Array = BUILDINGS.get(art, ["shop"])
	var pick: String = opts[seed % opts.size()]
	if has(pick):
		return pick
	for o in opts:
		if has(o):
			return o
	return "shop" if has("shop") else ""


static func aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var bb := mi.get_aabb()
		var xf := mi.transform
		var p: Node = mi.get_parent()
		while p != n and p is Node3D:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		bb = xf * bb
		out = bb if first else out.merge(bb)
		first = false
	return out


## Scale uniformly so the footprint fits `size` (x = length, y = width), standing on the ground,
## centred. Meshy vehicles face -X, so they get a half turn to face our forward (+X).
static func fit_vehicle(model: Node3D, size: Vector2) -> Node3D:
	var holder := Node3D.new()
	var bb := aabb(model)
	if bb.size.x > 0.0:
		var long_x := bb.size.x >= bb.size.z
		var length := bb.size.x if long_x else bb.size.z
		var width := bb.size.z if long_x else bb.size.x
		var k := minf(size.x / length, size.y / width)
		model.scale = Vector3.ONE * k
		model.position = Vector3(-bb.get_center().x * k, -bb.position.y * k, -bb.get_center().z * k)
		holder.rotation.y = PI if long_x else PI * 0.5
	holder.add_child(model)
	var root := Node3D.new()
	root.add_child(holder)
	return root


static func fit_height(model: Node3D, h: float) -> void:
	var bb := aabb(model)
	if bb.size.y > 0.0:
		var k := h / bb.size.y
		model.scale = Vector3.ONE * k
		model.position = Vector3(-bb.get_center().x * k, -bb.position.y * k, -bb.get_center().z * k)


## Car paint shines: lower roughness and a touch of metal on every surface.
static func glossy(n: Node) -> void:
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		for s in mi.get_surface_override_material_count():
			var m: Material = mi.get_active_material(s)
			if m is StandardMaterial3D:
				var g: StandardMaterial3D = (m as StandardMaterial3D).duplicate()
				g.roughness = minf(g.roughness, 0.35)
				g.metallic = maxf(g.metallic, 0.25)
				g.metallic_specular = 0.7
				mi.set_surface_override_material(s, g)


## Hide a model beyond `far` metres (fades out), so the whole city can be built at once.
static func far_cull(n: Node, far: float) -> void:
	for c in n.find_children("*", "GeometryInstance3D", true, false):
		var g := c as GeometryInstance3D
		g.visibility_range_end = far
		g.visibility_range_end_margin = far * 0.12
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


## Shadows only from things that matter (buildings, vehicles); small props skip them.
static func no_shadow(n: Node) -> void:
	for c in n.find_children("*", "GeometryInstance3D", true, false):
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------- people ----------

## A rigged person: the model (with its own Walking animation), its own Running clip and the
## shared action pack (idle, talk, fight...) merged into one AnimationPlayer. Returns
## [root Node3D, AnimationPlayer or null].
func person(key: String, height := 1.75) -> Array:
	var m := make(key, CHARS)
	if m == null:
		m = make(key) # older unrigged model (art3d/tunde.glb)
	if m == null:
		return [null, null]
	if find_player(m) == null:
		fit_height(m, height) # unrigged model; rigged Meshy people are already at real height
	# (A skinned mesh's node carries a 0.01 scale that skinning ignores, so its AABB lies.)
	var root := Node3D.new()
	root.add_child(m)
	var ap := find_player(m)
	if ap:
		_merge(ap, make(key + "_run", CHARS), { "run": "" })
		_merge_pack(ap)
		for a in ap.get_animation_list():
			var anim := ap.get_animation(a)
			if not String(a).to_lower() in ["dead", "hit", "punch", "wave"]:
				anim.loop_mode = Animation.LOOP_LINEAR
	return [root, ap]


static func find_player(n: Node) -> AnimationPlayer:
	var found := n.find_children("*", "AnimationPlayer", true, false)
	return found[0] as AnimationPlayer if not found.is_empty() else null


## Copy animations from another rigged scene into `ap` (same Meshy skeleton, so the same bone
## paths). `rename` maps a wanted name to a substring of the source name ("" = first clip).
func _merge(ap: AnimationPlayer, src: Node, rename: Dictionary) -> void:
	if src == null:
		return
	var sp := find_player(src)
	if sp:
		var lib := _lib(ap)
		for want: String in rename:
			var hit := ""
			for a in sp.get_animation_list():
				if hit == "" and (rename[want] == "" or String(rename[want]) in String(a).to_lower()):
					hit = a
			if hit != "" and not lib.has_animation(want):
				lib.add_animation(want, _retarget(sp.get_animation(hit).duplicate(), sp, ap))
	src.free()


func _merge_pack(ap: AnimationPlayer) -> void:
	if not _anim_checked:
		_anim_checked = true
		var pack := make("anim_pack", CHARS)
		if pack:
			var sp := find_player(pack)
			if sp:
				_anim_lib = AnimationLibrary.new()
				for a in sp.get_animation_list():
					var low := String(a).to_lower()
					var nm := low
					for k: String in PACK_NAMES:
						if k in low:
							nm = PACK_NAMES[k]
							break
					_anim_lib.add_animation(nm, sp.get_animation(a).duplicate())
				_pack_root_path = _skeleton_path(sp)
			pack.free()
	if _anim_lib == null:
		return
	var lib := _lib(ap)
	var here := _skeleton_path(ap)
	for nm in _anim_lib.get_animation_list():
		if not lib.has_animation(nm):
			var a: Animation = _anim_lib.get_animation(nm).duplicate()
			_repath(a, _pack_root_path, here)
			lib.add_animation(nm, a)


var _pack_root_path := ""
## Meshy's clip names in the action pack -> the short names the game plays.
const PACK_NAMES := { "wave": "wave", "sit": "sit", "dead": "dead", "hit": "hit", "motivational": "cheer", "phone": "phone", "punch": "punch", "angry": "argue", "talk": "talk", "idle": "idle" }


static func _lib(ap: AnimationPlayer) -> AnimationLibrary:
	if not ap.has_animation_library(""):
		ap.add_animation_library("", AnimationLibrary.new())
	return ap.get_animation_library("")


## Path from an AnimationPlayer's root node to its skeleton ("Armature/Skeleton3D").
static func _skeleton_path(ap: AnimationPlayer) -> String:
	var root := ap.get_node(ap.root_node)
	var sk := root.find_children("*", "Skeleton3D", true, false)
	return String(root.get_path_to(sk[0])) if not sk.is_empty() else ""


func _retarget(a: Animation, from: AnimationPlayer, to: AnimationPlayer) -> Animation:
	_repath(a, _skeleton_path(from), _skeleton_path(to))
	return a


static func _repath(a: Animation, from: String, to: String) -> void:
	if from == "" or to == "" or from == to:
		return
	for t in a.get_track_count():
		var p := String(a.track_get_path(t))
		if p.begins_with(from + ":"):
			a.track_set_path(t, NodePath(to + p.substr(from.length())))


## Play a clip by name if the player has it (crossfading); falls back to `fallback`.
static func play(ap: AnimationPlayer, name: String, fallback := "", speed := 1.0) -> void:
	if ap == null:
		return
	var pick := name if ap.has_animation(name) else ""
	if pick == "":
		for a in ap.get_animation_list():
			if pick == "" and name in String(a).to_lower():
				pick = a
	if pick == "" and fallback != "":
		play(ap, fallback, "", speed)
		return
	if pick == "":
		return
	if ap.current_animation != pick:
		ap.play(pick, 0.2, speed)
	else:
		ap.speed_scale = speed
