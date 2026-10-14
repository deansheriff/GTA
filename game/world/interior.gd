class_name Interior
extends CanvasLayer
## Painted interiors (owambe hall, later Mama Chief's house): one top-down painting on its own layer
## over the street, with the hero, story NPCs and ambient guests walking on it. Coordinates are the
## painting's pixels ("room" space); hotspots name the places missions point at.

const WalkerScript := preload("res://actors/walker.gd")
const ROOMS := {
	"owambe": {
		"art": "interiors/owambe-hall.jpg", "size": Vector2(1536, 1024),
		"walk": Rect2(80, 110, 1376, 860),
		"blocked": [Rect2(230, 770, 1075, 115), Rect2(500, 0, 540, 270)],
		"round": [[Vector2(290, 240), 88.0], [Vector2(265, 420), 88.0], [Vector2(240, 600), 88.0], [Vector2(1240, 240), 88.0], [Vector2(1265, 420), 88.0], [Vector2(1290, 600), 88.0]],
		"hotspots": { "door": Vector2(768, 950), "buffet": Vector2(768, 735), "dance": Vector2(768, 520), "stage": Vector2(768, 320), "high-table": Vector2(700, 205), "tables-left": Vector2(420, 520), "tables-right": Vector2(1110, 520) },
		"guests": 14,
	},
	"compound": {
		"art": "interiors/compound-party.jpg", "size": Vector2(1536, 1024),
		"walk": Rect2(60, 120, 1420, 860),
		"blocked": [Rect2(360, 730, 630, 200), Rect2(500, 0, 390, 280), Rect2(0, 150, 500, 280), Rect2(1000, 250, 500, 260), Rect2(1000, 0, 536, 190)],
		"round": [[Vector2(110, 700), 90.0], [Vector2(1120, 850), 100.0], [Vector2(140, 460), 70.0], [Vector2(330, 520), 70.0], [Vector2(1120, 575), 70.0], [Vector2(1300, 660), 70.0]],
		"hotspots": { "door": Vector2(300, 860), "gate": Vector2(300, 860), "tents-left": Vector2(450, 640), "tents-right": Vector2(1060, 720), "dance": Vector2(730, 500), "high-table": Vector2(690, 310), "study": Vector2(1160, 240), "buffet": Vector2(680, 690) },
		"guests": 16,
	},
	"stadium": {
		"art": "interiors/stadium.jpg", "size": Vector2(1536, 1024),
		"walk": Rect2(300, 200, 900, 690),
		"blocked": [Rect2(560, 0, 400, 205)],
		"round": [],
		"hotspots": { "door": Vector2(480, 790), "gate": Vector2(480, 790), "convoy-exit": Vector2(330, 840), "stage": Vector2(770, 230), "mic": Vector2(620, 260), "stand": Vector2(430, 520), "crowd": Vector2(770, 520) },
		"guests": 22,
	},
}
const HERO_SCALE := 1.55 # people are a touch larger than the street scale inside

var active := false
var room_id := ""
var player: Node2D
var waypoint := Vector2.INF
var _room: Node2D
var _bg: ColorRect
var _art: Sprite2D
var _dark: ColorRect
var _marker: Node2D
var _guests: Array[Node2D] = []
var _npcs := {}
var _def := {}
var _rng := RandomNumberGenerator.new()
var _tap_target := Vector2.INF
var _scale := 1.0


func _ready() -> void:
	layer = 2
	visible = false
	_bg = ColorRect.new()
	_bg.color = Color("#0d0a07")
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_room = Node2D.new()
	_room.y_sort_enabled = true
	add_child(_room)
	_art = Sprite2D.new()
	_art.centered = false
	# Origin at the top edge: in the y-sorted room the painting always sorts behind the people.
	_room.add_child(_art)
	_marker = Node2D.new()
	_marker.z_index = 5
	_marker.draw.connect(_draw_marker)
	_room.add_child(_marker)
	_dark = ColorRect.new()
	_dark.color = Color(0.02, 0.02, 0.06, 0.0)
	_dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dark)


func enter(id: String, spawn: String, hero_sheet: String, mat: Material) -> void:
	_def = ROOMS[id]
	room_id = id
	active = true
	visible = true
	_art.texture = Art.tex(_def["art"])
	if player == null:
		player = WalkerScript.new()
		player.scale = Vector2(HERO_SCALE, HERO_SCALE)
		player.material = mat
		_room.add_child(player)
	set_hero_sheet(hero_sheet)
	player.position = where(spawn)
	player.target = Vector2.INF
	_spawn_guests(mat)
	_layout()


func exit() -> void:
	active = false
	visible = false
	clear_npcs()
	for g in _guests:
		g.queue_free()
	_guests.clear()
	waypoint = Vector2.INF
	set_dark(false)


func set_hero_sheet(path: String) -> void:
	if player:
		player.use_hero_sheet(path)


func where(spot: String) -> Vector2:
	var d: Dictionary = _def if not _def.is_empty() else ROOMS["owambe"]
	return d["hotspots"].get(spot.trim_prefix("room:"), d["hotspots"]["door"])


func set_dark(on: bool) -> void:
	_dark.color.a = 0.86 if on else 0.0


func add_npc(id: String, node: Node2D, pos: Vector2) -> void:
	node.position = pos
	node.scale = Vector2(HERO_SCALE, HERO_SCALE)
	_room.add_child(node)
	_npcs[id] = node


func npc(id: String) -> Node2D:
	return _npcs.get(id, null)


func clear_npcs(id := "") -> void:
	for k in _npcs.keys():
		if id == "" or k == id:
			(_npcs[k] as Node).queue_free()
			_npcs.erase(k)


func walkable(p: Vector2) -> bool:
	if _def.is_empty() or not (_def["walk"] as Rect2).has_point(p):
		return false
	for r in _def["blocked"]:
		if (r as Rect2).has_point(p):
			return false
	for c in _def["round"]:
		if p.distance_to(c[0]) < float(c[1]):
			return false
	return true


func _spawn_guests(mat: Material) -> void:
	for g in _guests:
		g.queue_free()
	_guests.clear()
	_rng.seed = 404
	for i in int(_def.get("guests", 0)):
		var g: Node2D = WalkerScript.new()
		g.use_pedestrian(_rng.randi_range(0, 15))
		g.scale = Vector2(HERO_SCALE, HERO_SCALE)
		g.speed = _rng.randf_range(30.0, 60.0)
		g.material = mat
		for t in 20:
			var p := Vector2(_rng.randf_range(120, 1420), _rng.randf_range(300, 760))
			if walkable(p):
				g.position = p
				break
		_room.add_child(g)
		_guests.append(g)


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	# Fill the screen height; the hall pans sideways with the hero on narrow screens.
	_scale = maxf(vp.y / (_def["size"] as Vector2).y, vp.x / (_def["size"] as Vector2).x) * 1.25
	_room.scale = Vector2(_scale, _scale)


## Walk the hero (joystick/keys) or toward a tap; keep the camera on them.
func step(delta: float, dir: Vector2) -> void:
	if not active:
		return
	var move := dir
	if move == Vector2.ZERO and _tap_target != Vector2.INF:
		var to := _tap_target - player.position
		if to.length() < 6.0:
			_tap_target = Vector2.INF
		else:
			move = to.normalized()
	elif move != Vector2.ZERO:
		_tap_target = Vector2.INF
	var speed: float = 210.0
	player.velocity = move * speed
	if move != Vector2.ZERO:
		var next: Vector2 = player.position + player.velocity * delta
		if walkable(next):
			player.position = next
		elif walkable(Vector2(next.x, player.position.y)):
			player.position.x = next.x
		elif walkable(Vector2(player.position.x, next.y)):
			player.position.y = next.y
		else:
			_tap_target = Vector2.INF
		if absf(move.x) > absf(move.y) * 1.1:
			player.facing = "side"
			player.flip = move.x < 0.0
		else:
			player.facing = "down" if move.y > 0.0 else "up"
		player.anim_t += delta * 10.0
	else:
		player.anim_t = 0.0
	player._update_sprite()
	# Ambient guests mill about the tables and dance floor.
	for g in _guests:
		if g.target == Vector2.INF:
			g.idle_t -= delta
			if g.idle_t <= 0.0:
				var t: Vector2 = g.position + Vector2(_rng.randf_range(-120, 120), _rng.randf_range(-80, 80))
				if walkable(t):
					g.target = t
				g.idle_t = _rng.randf_range(1.0, 4.0)
		else:
			var to: Vector2 = g.target - g.position
			if to.length() < 4.0:
				g.target = Vector2.INF
				g.velocity = Vector2.ZERO
			else:
				g.velocity = to.normalized() * g.speed
				g.position += g.velocity * delta
				g.facing = "side"
				g.anim_t += delta * 8.0
		g._update_sprite()
	var vp := get_viewport().get_visible_rect().size
	var size: Vector2 = (_def["size"] as Vector2) * _scale
	var want := vp * 0.5 - player.position * _scale
	_room.position = Vector2(clampf(want.x, vp.x - size.x, 0.0), clampf(want.y, vp.y - size.y, 0.0))
	_marker.queue_redraw()


func tap(screen_pos: Vector2) -> void:
	_tap_target = (screen_pos - _room.position) / _scale


func focus() -> Vector2:
	return player.position if player else Vector2.ZERO


func _draw_marker() -> void:
	if waypoint == Vector2.INF:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var r := 34.0 + sin(t * 4.0) * 5.0
	_marker.draw_arc(waypoint, r, 0, TAU, 32, Color("#e0a91c"), 6.0, true)
	_marker.draw_arc(waypoint, r, 0, TAU, 32, Color("#1d1611"), 2.0, true)
	_marker.draw_circle(waypoint + Vector2(0, -r - 22 + sin(t * 5.0) * 4.0), 9.0, Color("#e0a91c"))
