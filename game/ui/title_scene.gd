class_name TitleScene
extends Control
## The living title painting (owner request 2026-10-15: "it should come alive… do not change the
## scene"). The splash painting stays exactly as painted; on top of it:
##  - a shader moves its regions (shaders/title_alive.gdshader),
##  - people walk up and down the street and okadas and kekes pass, in perspective, slipping
##    behind cut-outs of the foreground danfo, mama and boy (Polygon2D pieces of the same painting),
##  - birds cross the sky, the danfo puffs exhaust and the street lamp flickers (NEPA!).
## Everything is placed in painting pixels; the stage scales like TextureRect's "keep aspect covered".

const IMG := Vector2(1280, 853)
const HORIZON := 560.0
const TINT := Color(0.92, 0.82, 0.68)

## Foreground cut-outs, painting pixels. base = where they touch the ground (depth for y-sorting).
const CUTOUTS := {
	"danfo": { "base": 836.0, "poly": [Vector2(262, 466), Vector2(330, 452), Vector2(650, 452), Vector2(722, 470), Vector2(772, 502), Vector2(791, 560), Vector2(793, 700), Vector2(768, 758), Vector2(738, 790), Vector2(692, 800), Vector2(612, 836), Vector2(560, 838), Vector2(536, 792), Vector2(520, 776), Vector2(300, 762), Vector2(268, 746), Vector2(248, 720), Vector2(244, 560), Vector2(252, 500)] },
	"mama": { "base": 853.0, "poly": [Vector2(52, 420), Vector2(92, 378), Vector2(162, 374), Vector2(192, 410), Vector2(202, 470), Vector2(256, 540), Vector2(276, 620), Vector2(272, 700), Vector2(252, 760), Vector2(254, 853), Vector2(36, 853), Vector2(36, 760), Vector2(14, 700), Vector2(18, 600), Vector2(52, 520), Vector2(48, 470)] },
	"boy": { "base": 853.0, "poly": [Vector2(1140, 478), Vector2(1180, 462), Vector2(1240, 462), Vector2(1280, 492), Vector2(1280, 853), Vector2(1082, 853), Vector2(1066, 762), Vector2(1030, 752), Vector2(1012, 702), Vector2(1036, 640), Vector2(1056, 590), Vector2(1058, 520), Vector2(1104, 520), Vector2(1108, 562), Vector2(1126, 520)] },
}

## Street paths in painting pixels (feet positions), from -> to. Toward the viewer uses front
## sprites, away uses back sprites. Paths that start or end behind a cut-out fade there.
const WALK_TOWARD := [[Vector2(900, 562), Vector2(735, 706)], [Vector2(955, 562), Vector2(1088, 802)], [Vector2(926, 562), Vector2(902, 905)]]
const WALK_AWAY := [[Vector2(1088, 802), Vector2(932, 562)], [Vector2(742, 706), Vector2(896, 562)], [Vector2(916, 905), Vector2(942, 562)]]
const RIDE := {
	"okada-f": [Vector2(884, 560), Vector2(908, 980), 2.3, 0.8],
	"okada-b": [Vector2(934, 980), Vector2(906, 560), 2.0, 0.8],
	"keke-f": [Vector2(876, 560), Vector2(884, 1000), 1.5, 0.9],
	"keke-b": [Vector2(900, 1010), Vector2(892, 560), 1.3, 0.9],
}
const FRONT := ["walk-f-orange", "walk-f-jersey", "walk-f-agbada", "walk-f-school"]
const BACK := ["walk-b-bread", "walk-b-sack", "walk-b-gown", "walk-b-boy"]

var _stage := Node2D.new()
var _street := Node2D.new() # y-sorted: movers and cut-outs
var _fx: Node2D
var _glow: Node2D
var _mat: ShaderMaterial
var _tex := {}
var _walk_t := 0.0
var _ride_t := 2.5
var _ride_next := 0
var _rng := RandomNumberGenerator.new()


## Height in painting pixels of a person standing with their feet at y (fitted to the painted people).
static func person_h(y: float) -> float:
	return clampf(60.0 + (y - HORIZON) * 0.78, 34.0, 420.0)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_rng.randomize()
	var painting := Art.tex("story/panel-splash.jpg")
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/title_alive.gdshader")
	var noise := FastNoiseLite.new()
	noise.frequency = 0.012
	var nt := NoiseTexture2D.new()
	nt.noise = noise
	nt.seamless = true
	nt.width = 256
	nt.height = 256
	_mat.set_shader_parameter("noise_tex", nt)
	_mat.set_shader_parameter("img", IMG)
	_mat.set_shader_parameter("motion", 0.6 if Settings.get_value("reduced_motion", false) else 1.0)
	add_child(_stage)
	var bg := Sprite2D.new()
	bg.texture = painting
	bg.centered = false
	bg.material = _mat
	if painting:
		bg.scale = IMG / painting.get_size()
	_stage.add_child(bg)
	_street.y_sort_enabled = true
	_stage.add_child(_street)
	for k in CUTOUTS:
		var c: Dictionary = CUTOUTS[k]
		var poly := Polygon2D.new()
		var pts := PackedVector2Array()
		var uv := PackedVector2Array()
		var tex_scale := (painting.get_size() / IMG) if painting else Vector2.ONE
		for v: Vector2 in c["poly"]:
			pts.append(v - Vector2(0, c["base"]))
			uv.append(v * tex_scale)
		poly.polygon = pts
		poly.uv = uv
		poly.texture = painting
		poly.material = _mat
		poly.position = Vector2(0, c["base"])
		_street.add_child(poly)
	for n in FRONT + BACK + RIDE.keys():
		_tex[n] = Art.tex("title/%s.png" % n)
	_glow = _Glow.new()
	_stage.add_child(_glow)
	_fx = _Fx.new()
	_stage.add_child(_fx)
	resized.connect(_fit)
	_fit()
	# Start mid-scene: people already on the street when the title appears.
	for i in 5:
		_spawn_walker(_rng.randf_range(0.1, 0.8))
	_spawn_ride(0.35)


func _fit() -> void:
	var s := maxf(size.x / IMG.x, size.y / IMG.y)
	_stage.scale = Vector2(s, s)
	_stage.position = (size - IMG * s) * 0.5


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	_walk_t -= dt
	if _walk_t <= 0.0:
		_walk_t = _rng.randf_range(1.0, 2.6)
		if _street.get_child_count() - CUTOUTS.size() < 9:
			_spawn_walker(0.0)
	_ride_t -= dt
	if _ride_t <= 0.0:
		_ride_t = _rng.randf_range(4.5, 8.0)
		_spawn_ride(0.0)


func _spawn_walker(progress: float) -> void:
	var toward := _rng.randf() < 0.5
	var paths: Array = WALK_TOWARD if toward else WALK_AWAY
	var path: Array = paths[_rng.randi() % paths.size()]
	var names: Array = FRONT if toward else BACK
	var n: String = names[_rng.randi() % names.size()]
	_add_mover(_tex.get(n), path[0], path[1], _rng.randf_range(0.6, 0.85), 1.0, true, progress)


func _spawn_ride(progress: float) -> void:
	var keys := RIDE.keys()
	var k: String = keys[_ride_next % keys.size()]
	_ride_next += 1 + (_rng.randi() % 2)
	var r: Array = RIDE[k]
	_add_mover(_tex.get(k), r[0], r[1], r[2], r[3], false, progress)


func _add_mover(tex: Texture2D, from: Vector2, to: Vector2, speed: float, size_k: float, walking: bool, progress: float) -> void:
	if tex == null:
		return
	var m := _Mover.new()
	m.tex = tex
	m.from = from
	m.to = to
	m.speed = speed
	m.size_k = size_k
	m.walking = walking
	m.phase = _rng.randf() * TAU
	m.u = progress
	m.position = from.lerp(to, progress)
	_street.add_child(m)


## One person or vehicle crossing the painting. Feet at the node's origin; size from perspective.
class _Mover extends Node2D:
	var tex: Texture2D
	var from: Vector2
	var to: Vector2
	var speed := 0.7 # body heights per second
	var size_k := 1.0
	var walking := true
	var phase := 0.0
	var u := 0.0

	func _process(delta: float) -> void:
		var dist := from.distance_to(to)
		var h: float = TitleScene.person_h(position.y)
		u += minf(delta, 0.05) * speed * h / dist
		if u >= 1.0:
			queue_free()
			return
		position = from.lerp(to, u)
		phase += delta * (7.5 if walking else 40.0)
		# Fade near the horizon (they melt into the painted crowd) and at the ends of paths.
		var fade := minf(smoothstep(0.0, 0.07, u), smoothstep(1.0, 0.9, u))
		modulate.a = fade * smoothstep(TitleScene.HORIZON - 4.0, TitleScene.HORIZON + 30.0, position.y)
		queue_redraw()

	func _draw() -> void:
		var h: float = TitleScene.person_h(position.y) * size_k
		var w := h * tex.get_width() / float(tex.get_height())
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 0.22))
		draw_circle(Vector2.ZERO, w * 0.36, Color(0.1, 0.06, 0.03, 0.28))
		draw_set_transform(Vector2.ZERO)
		var bob := 0.0
		var tilt := 0.0
		if walking:
			bob = -absf(sin(phase)) * h * 0.022
			tilt = sin(phase) * 0.018
		else:
			bob = sin(phase) * h * 0.004
		draw_set_transform(Vector2(0, bob), tilt)
		draw_texture_rect(tex, Rect2(-w * 0.5, -h, w, h), false, TitleScene.TINT)
		draw_set_transform(Vector2.ZERO)


## Front effects: birds over the lagoon and danfo exhaust.
class _Fx extends Node2D:
	var birds: Array = []
	var puffs: Array = []
	var puff_t := 0.0

	func _ready() -> void:
		for i in 5:
			birds.append(_bird(randf_range(300, 1280)))

	func _bird(x: float) -> Dictionary:
		return { "p": Vector2(x, randf_range(160, 300)), "v": randf_range(22, 40), "s": randf_range(5, 9), "ph": randf() * TAU }

	func _process(delta: float) -> void:
		var dt := minf(delta, 0.05)
		for i in birds.size():
			var b: Dictionary = birds[i]
			b["p"] += Vector2(-b["v"], sin(b["ph"] * 0.3) * 4.0) * dt
			b["ph"] += dt * 9.0
			if b["p"].x < 230.0:
				birds[i] = _bird(randf_range(1290, 1500))
		puff_t -= dt
		if puff_t <= 0.0:
			puff_t = randf_range(0.25, 0.5)
			puffs.append({ "p": Vector2(786, 772), "r": 4.0, "a": 0.32 })
		for p: Dictionary in puffs:
			p["p"] += Vector2(26, -14) * dt
			p["r"] += 9.0 * dt
			p["a"] -= 0.16 * dt
		puffs = puffs.filter(func(p: Dictionary) -> bool: return p["a"] > 0.0)
		queue_redraw()

	func _draw() -> void:
		for p: Dictionary in puffs:
			draw_circle(p["p"], p["r"], Color(0.62, 0.58, 0.54, p["a"]))
		var ink := Color(0.15, 0.09, 0.06, 0.75)
		for b: Dictionary in birds:
			var flap: float = sin(b["ph"]) * 0.6
			var s: float = b["s"]
			var c: Vector2 = b["p"]
			draw_polyline(PackedVector2Array([c + Vector2(-s, -s * (0.3 + flap)), c, c + Vector2(s, -s * (0.3 + flap))]), ink, 1.6, true)


## Additive glows: the street lamp (NEPA flicker).
class _Glow extends Node2D:
	var lamp := 1.0
	var blink_t := 6.0
	var blinks := 0
	var tex: GradientTexture2D

	func _ready() -> void:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 0.82, 0.45, 0.9))
		g.set_color(1, Color(1.0, 0.6, 0.2, 0.0))
		tex = GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 128
		tex.height = 128

	func _process(delta: float) -> void:
		blink_t -= delta
		if blink_t <= 0.0:
			if blinks <= 0:
				blinks = randi_range(2, 4)
			blinks -= 1
			lamp = 0.0 if lamp > 0.5 else 1.0
			blink_t = randf_range(0.06, 0.18) if blinks > 0 else randf_range(6.0, 12.0)
			if blinks <= 0:
				lamp = 1.0
		queue_redraw()

	func _draw() -> void:
		var k := lamp * (0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.011))
		draw_texture_rect(tex, Rect2(Vector2(1127, 94) - Vector2(46, 46), Vector2(92, 92)), false, Color(1, 1, 1, 0.55 * k))
