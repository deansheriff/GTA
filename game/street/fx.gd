class_name StreetFx
extends Node2D
## World-space effects for the street systems: comic pop-ups ("GBAM!"), crash debris, engine
## smoke, puddle splashes and short speech bubbles over pedestrians. Cheap immediate drawing.

const INK := Color("#1d1611")
const PAPER := Color("#f1e6c8")

var _pops: Array = [] # {text, pos, t, life, col, size}
var _bits: Array = [] # {pos, vel, t, col, size}
var _puffs: Array = [] # {pos, vel, r, a, col}
var _bubbles: Array = [] # {node, text, t}
var _font: Font


func _ready() -> void:
	z_index = 40
	_font = ThemeDB.fallback_font


func pop(text: String, at: Vector2, col := Color("#e0a91c"), size := 44, life := 0.9) -> void:
	_pops.append({ "text": text, "pos": at, "t": 0.0, "life": life, "col": col, "size": size })


func debris(at: Vector2, col: Color, n := 10) -> void:
	for i in n:
		var v := Vector2.from_angle(randf() * TAU) * randf_range(60.0, 220.0)
		_bits.append({ "pos": at, "vel": v, "t": 0.0, "col": col.darkened(randf() * 0.4), "size": randf_range(2.0, 5.0) })


func smoke(at: Vector2, dark := 0.5) -> void:
	_puffs.append({ "pos": at, "vel": Vector2(randf_range(-12, 12), randf_range(-42, -24)), "r": 9.0, "a": 0.6, "col": Color(0.86, 0.85, 0.82).lerp(Color(0.18, 0.17, 0.16), dark), "grow": 22.0 })


func splash(at: Vector2) -> void:
	for i in 6:
		_puffs.append({ "pos": at + Vector2(randf_range(-20, 20), randf_range(-8, 8)), "vel": Vector2(randf_range(-40, 40), randf_range(-60, -20)), "r": 4.0, "a": 0.6, "col": Color(0.75, 0.85, 0.9) })


## A speech bubble that follows a node for a few seconds.
func say(node: Node2D, text: String, seconds := 2.5) -> void:
	for b: Dictionary in _bubbles:
		if b["node"] == node:
			b["text"] = text
			b["t"] = seconds
			return
	_bubbles.append({ "node": node, "text": text, "t": seconds })


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	for p: Dictionary in _pops:
		p["t"] += dt
	_pops = _pops.filter(func(p: Dictionary) -> bool: return p["t"] < p["life"])
	for b: Dictionary in _bits:
		b["t"] += dt
		b["pos"] += b["vel"] * dt
		b["vel"] *= pow(0.05, dt)
	_bits = _bits.filter(func(b: Dictionary) -> bool: return b["t"] < 1.2)
	for p: Dictionary in _puffs:
		p["pos"] += p["vel"] * dt
		p["r"] += float(p.get("grow", 14.0)) * dt
		p["a"] -= 0.35 * dt
	_puffs = _puffs.filter(func(p: Dictionary) -> bool: return p["a"] > 0.0)
	for b: Dictionary in _bubbles:
		b["t"] -= dt
	_bubbles = _bubbles.filter(func(b: Dictionary) -> bool: return b["t"] > 0.0 and is_instance_valid(b["node"]))
	if not (_pops.is_empty() and _bits.is_empty() and _puffs.is_empty() and _bubbles.is_empty()):
		queue_redraw()
	elif get_meta("dirty", true):
		set_meta("dirty", false)
		queue_redraw()


func _draw() -> void:
	set_meta("dirty", true)
	for p: Dictionary in _puffs:
		draw_circle(p["pos"], p["r"], Color(p["col"].r, p["col"].g, p["col"].b, maxf(0.0, p["a"])))
	for b: Dictionary in _bits:
		var a: float = 1.0 - b["t"] / 1.2
		draw_rect(Rect2(b["pos"] - Vector2.ONE * b["size"] * 0.5, Vector2.ONE * b["size"]), Color(b["col"].r, b["col"].g, b["col"].b, a))
	for p: Dictionary in _pops:
		var k: float = p["t"] / p["life"]
		var sc := 0.6 + 0.6 * minf(1.0, k * 6.0) - 0.15 * maxf(0.0, k - 0.6)
		var size := int(float(p["size"]) * sc)
		var w := _font.get_string_size(p["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var at: Vector2 = p["pos"] + Vector2(-w * 0.5, -30.0 * k)
		var a := 1.0 - maxf(0.0, (k - 0.7) / 0.3)
		draw_string_outline(_font, at, p["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, 8, Color(INK, a))
		draw_string(_font, at, p["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(p["col"], a))
	for b: Dictionary in _bubbles:
		var n: Node2D = b["node"]
		var w := _font.get_string_size(b["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var at := n.position + Vector2(-w * 0.5 - 8.0, -86.0)
		draw_rect(Rect2(at, Vector2(w + 16.0, 24.0)), Color(PAPER, 0.95))
		draw_rect(Rect2(at, Vector2(w + 16.0, 24.0)), INK, false, 2.0)
		draw_string(_font, at + Vector2(8, 17), b["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, INK)
