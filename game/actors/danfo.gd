extends Node2D
## "Baba God Dey": the yellow danfo, drawn as a 3D box in top-down 3/4 so its sides show correctly
## at any heading (smooth free driving, decision D-004). Node origin = centre of the ground footprint.

const K := Layout.HEIGHT_K
const GLASS := Color("#9fc4cf")
## Vehicle types: size (px), body colour, stripe. Painted art at art/vehicles/<kind>.png if present.
const KINDS := {
	"danfo": { "len": 132.0, "wid": 58.0, "h": 44.0, "body": Color("#e0a91c"), "stripe": true },
	"car": { "len": 104.0, "wid": 50.0, "h": 30.0, "body": Color("#2f6f99"), "stripe": false },
	"keke": { "len": 64.0, "wid": 40.0, "h": 34.0, "body": Color("#3f8a3a"), "stripe": false },
	"okada": { "len": 46.0, "wid": 16.0, "h": 22.0, "body": Color("#a8382c"), "stripe": false },
}

var kind := "danfo"
var LENGTH := 132.0
var WIDTH := 58.0
var HEIGHT := 44.0
var BODY := Color("#e0a91c")

var heading := 0.0 # radians, 0 = east, y points south
var speed := 0.0 # px / s
var _wedged_t := 0.0
var max_road := 380.0
var max_off := 150.0
var limit := INF # fuel and damage cap the top speed (street/vehicle_care.gd)
var _art: Sprite2D
var _paint := Color(0, 0, 0, 0)


func set_kind(k: String, tint := Color(0, 0, 0, 0)) -> void:
	kind = k
	var d: Dictionary = KINDS.get(k, KINDS["danfo"])
	LENGTH = d["len"]
	WIDTH = d["wid"]
	HEIGHT = d["h"]
	BODY = tint if tint.a > 0.0 else d["body"]


func _ready() -> void:
	refresh_art()


## (Re)build the painted art for the current kind: hustles swap the danfo for a keke or okada.
func refresh_art() -> void:
	if _art:
		_art.queue_free()
		_art = null
	var t := Art.tex("vehicles/%s.png" % kind)
	if t:
		# Painted top-down danfo (front to the right), rotated freely with the heading.
		_art = Sprite2D.new()
		_art.texture = t
		# True top-down painting (front to the right): rotates cleanly at any heading.
		var sc := (LENGTH + 8.0) / float(t.get_width())
		_art.scale = Vector2(sc, sc)
		_art.position = Vector2(0, -HEIGHT * K * 0.35) # lifted a little: the roof sits above the road
		if kind == "car" and BODY != KINDS["car"]["body"]:
			_art.self_modulate = BODY.lightened(0.45) # vary the paint a little
		add_child(_art)
		if _paint.a > 0.0:
			set_paint(_paint)
	queue_redraw()


## Custom paint for a danfo (M10): recolours the yellow body only (shaders/bus_paint.gdshader).
func set_paint(c: Color) -> void:
	_paint = c
	if _art == null:
		return
	if c.a <= 0.0:
		_art.material = null
		return
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/bus_paint.gdshader")
	m.set_shader_parameter("paint", c)
	_art.material = m


func _process(_delta: float) -> void:
	if _art:
		_art.rotation = heading


func drive(delta: float, input: Vector2, world: MapData) -> String:
	var m := MapData.shared()
	var on_road := m.is_roadlike(m.surface_at(position))
	var top_speed := minf(max_road if on_road else max_off, limit)
	if input.length() > 0.15:
		var want := input.angle()
		var diff := wrapf(want - heading, -PI, PI)
		var turn := 2.6 * clampf(0.3 + absf(speed) / 160.0, 0.0, 1.0)
		heading += clampf(diff, -turn * delta, turn * delta)
		var goal := -120.0 if absf(diff) > 2.4 else top_speed * minf(input.length(), 1.0)
		speed += clampf(goal - speed, -520.0 * delta, 260.0 * delta)
	else:
		speed *= pow(0.18, delta)
		if absf(speed) < 3.0:
			speed = 0.0
	if speed > top_speed:
		speed = lerpf(speed, top_speed, minf(1.0, 3.0 * delta))
	var fwd := Vector2.from_angle(heading)
	var next := position + fwd * speed * delta
	var half := Vector2(LENGTH, WIDTH) * 0.46
	var event := ""
	if not world.body_blocked(next, heading, half):
		position = next
		_wedged_t = 0.0
	elif world.body_blocked(position, heading, half) and not world.is_blocked(next):
		# Already touching something (turned into a pole, pushed by traffic): never trap the bus;
		# any move that keeps the centre clear is allowed so you can always drive out.
		position = next
	elif absf(speed) > 90.0:
		speed = -speed * 0.3
		event = "crash"
	else:
		speed = 0.0
		# Wedged with the stick held for a while: hop to the nearest clear spot (last resort).
		if input.length() > 0.15:
			_wedged_t += delta
			if _wedged_t > 1.5:
				_wedged_t = 0.0
				_unwedge(world, half)
	queue_redraw()
	return event


func _unwedge(world: MapData, half: Vector2) -> void:
	for r: float in [24.0, 48.0, 72.0, 96.0, 128.0]:
		for i in 12:
			var p := position + Vector2.from_angle(i * TAU / 12.0) * r
			if not world.body_blocked(p, heading, half):
				position = p
				return


func _project(local: Vector3) -> Vector2:
	var p := Vector2(local.x, local.y).rotated(heading)
	return Vector2(p.x, p.y - local.z * K)


func _draw() -> void:
	var l := LENGTH * 0.5
	var w := WIDTH * 0.5
	var h := HEIGHT
	Ink.shadow(self, Vector2(10, 6), Vector2(66, 34), 0.36)
	if _art:
		return
	# Wheels peek out under the body.
	for c in [Vector3(l * 0.62, w, 7), Vector3(-l * 0.62, w, 7), Vector3(l * 0.62, -w, 7), Vector3(-l * 0.62, -w, 7)]:
		Ink.ellipse(self, _project(c), Vector2(9, 6), Color("#1c1a19"), 1.6, heading)
	# Side faces: [a, b] along the base, outward normal n.
	var faces := [
		{ "a": Vector3(-l, w, 0), "b": Vector3(l, w, 0), "n": Vector2(0, 1), "kind": "side" },
		{ "a": Vector3(l, -w, 0), "b": Vector3(-l, -w, 0), "n": Vector2(0, -1), "kind": "side" },
		{ "a": Vector3(l, w, 0), "b": Vector3(l, -w, 0), "n": Vector2(1, 0), "kind": "front" },
		{ "a": Vector3(-l, -w, 0), "b": Vector3(-l, w, 0), "n": Vector2(-1, 0), "kind": "back" },
	]
	for f in faces:
		var n: Vector2 = (f["n"] as Vector2).rotated(heading)
		if n.y <= 0.02:
			continue # faces away from the camera
		var a: Vector3 = f["a"]
		var b: Vector3 = f["b"]
		var at := func(u: float, v: float) -> Vector2:
			return _project(Vector3(lerpf(a.x, b.x, u), lerpf(a.y, b.y, u), v * h))
		var quad := func(u0: float, u1: float, v0: float, v1: float) -> PackedVector2Array:
			return PackedVector2Array([at.call(u0, v0), at.call(u1, v0), at.call(u1, v1), at.call(u0, v1)])
		var shade := 0.0 if f["kind"] == "side" else 0.08
		Ink.poly(self, quad.call(0.0, 1.0, 0.0, 1.0), BODY.darkened(0.12 + shade), 0.0)
		if KINDS.get(kind, {}).get("stripe", false):
			draw_colored_polygon(quad.call(0.0, 1.0, 0.36, 0.47), Color("#1a1a1a")) # the black danfo band
		if f["kind"] == "side":
			for k in 4:
				var u0 := 0.08 + k * 0.22
				Ink.poly(self, quad.call(u0, u0 + 0.18, 0.56, 0.88), GLASS.darkened(0.15), 1.2)
		elif f["kind"] == "front":
			Ink.poly(self, quad.call(0.1, 0.9, 0.55, 0.92), GLASS, 1.2)
			draw_colored_polygon(quad.call(0.06, 0.2, 0.18, 0.3), Color("#fff3b0"))
			draw_colored_polygon(quad.call(0.8, 0.94, 0.18, 0.3), Color("#fff3b0"))
		else:
			Ink.poly(self, quad.call(0.15, 0.85, 0.58, 0.88), GLASS.darkened(0.1), 1.2)
		var outline: PackedVector2Array = quad.call(0.0, 1.0, 0.0, 1.0)
		outline.append(outline[0])
		draw_polyline(outline, Ink.COLOR, Ink.W, true)
	# Roof seen from above, with two black stripes and a luggage rack.
	var roof := PackedVector2Array([_project(Vector3(l, w, h)), _project(Vector3(l, -w, h)), _project(Vector3(-l, -w, h)), _project(Vector3(-l, w, h))])
	Ink.poly(self, roof, BODY, Ink.W + 0.4)
	for t in ([-0.18, 0.18] if kind == "danfo" else []):
		draw_line(_project(Vector3(-l * 0.92, w * t * 2.0, h)), _project(Vector3(l * 0.92, w * t * 2.0, h)), Color("#1a1a1a"), 3.0)
	for t in ([-0.45, 0.0, 0.45] if kind == "danfo" else []):
		draw_line(_project(Vector3(l * t, w * 0.75, h + 3)), _project(Vector3(l * t, -w * 0.75, h + 3)), Color(0.15, 0.15, 0.15, 0.7), 2.0)
	# Windscreen hint at the front edge of the roof.
	Ink.poly(self, PackedVector2Array([_project(Vector3(l, w * 0.85, h)), _project(Vector3(l, -w * 0.85, h)), _project(Vector3(l - 14, -w * 0.8, h)), _project(Vector3(l - 14, w * 0.8, h))]), GLASS, 1.4)
