extends Node2D
## Chibi placeholder person in The Omins' proportions: big head, small body, thick ink outline.
## Used for the player hero and for NPC pedestrians. Real heroes become painted sprite sheets.

const SKINS := [Color("#4f3121"), Color("#5e3b27"), Color("#6b442d"), Color("#7a5034"), Color("#432a1c")]
const SHIRTS := [Color("#a8382c"), Color("#2f6f99"), Color("#2f8a52"), Color("#c8862a"), Color("#76418a"), Color("#22806f"), Color("#b55422"), Color("#d9d3c4")]
const ANKARA := [Color("#c96f24"), Color("#1f9a86"), Color("#84509a"), Color("#c4473a")]
const TROUSERS := [Color("#2b3440"), Color("#3a4250"), Color("#4e3a2c"), Color("#1d232b"), Color("#6b6e66")]

var look := {}
var speed := 150.0 # px / s
var velocity := Vector2.ZERO
var facing := "down" # down, up, side
var flip := false
var anim_t := 0.0
var anim_fps := 10.0
var target := Vector2.INF
var idle_t := 0.0
var _drawn_key := ""
var display_name := ""
var _spr: Sprite2D
var _sheet := "" # "hero" (4x3 walk: down, up, right) or "ped" (painted townsfolk)
var _ped_index := 0
var _ped_front: Texture2D
var _ped_side: Texture2D
var _base_y := 0.0
const SPRITE_H := 60.0 # on-screen height of a painted person, px


## Painted hero walk sheet (art/characters/*-walk.png + .json). Returns false if missing.
func use_hero_sheet(path: String) -> bool:
	var t := Art.tex(path)
	var info := Art.sheet_info(path)
	if t == null or info.is_empty():
		return false
	_make_sprite(t, int(info["cols"]), int(info["rows"]), float(info["frameH"]))
	_sheet = "hero"
	return true


## One of 16 painted townsfolk. 0-7 face the viewer (people standing or loitering),
## 8-15 are side-walking passers-by. Each person comes from one sheet only, so they never
## change identity when they turn.
var loiterer := false


func use_pedestrian(index: int) -> bool:
	var i := posmod(index, 16)
	loiterer = i < 8
	var path := "characters/pedestrians-a.png" if loiterer else "characters/pedestrians-b.png"
	var t := Art.tex(path)
	var info := Art.sheet_info(path)
	if t == null or info.is_empty():
		return false
	_ped_front = t if loiterer else null
	_ped_side = null if loiterer else t
	_ped_index = i % 8
	_make_sprite(t, int(info["cols"]), int(info["rows"]), float(info["frameH"]))
	_spr.frame = _ped_index
	_sheet = "ped"
	return true


func _make_sprite(t: Texture2D, cols: int, rows: int, frame_h: float) -> void:
	_spr = Sprite2D.new()
	_spr.texture = t
	_spr.hframes = cols
	_spr.vframes = rows
	var sc := SPRITE_H / frame_h
	_spr.scale = Vector2(sc, sc)
	# Frames have feet 2 px above their bottom edge: put that baseline on the node origin.
	_base_y = -(frame_h * 0.5 - 2.0) * sc
	_spr.position = Vector2(0, _base_y)
	add_child(_spr)
	queue_redraw()


func _update_sprite() -> void:
	if _spr == null:
		return
	var moving := velocity.length() > 1.0
	if _sheet == "hero":
		var row := 2 if facing == "side" else (1 if facing == "up" else 0)
		var phase := int(anim_t) % 4 if moving else 1
		_spr.frame = row * 4 + phase
		_spr.flip_h = facing == "side" and flip
		_spr.position.y = _base_y
	else:
		_spr.frame = _ped_index
		# Side-walkers face their direction of travel; loiterers always face the viewer.
		if not loiterer and absf(velocity.x) > 1.0:
			_spr.flip_h = velocity.x < 0.0
		# Painted townsfolk have one pose: a small step-bob sells the walk.
		_spr.position.y = _base_y - (absf(sin(anim_t * PI)) * 2.5 if moving else 0.0)


static func tunde() -> Dictionary:
	return { "skin": Color("#4f3121"), "top": Color("#a8382c"), "bottom": Color("#2b3440"), "hair": "low", "hair_col": Color("#111111"), "extra": "towel" }


static func random_look(seed: int) -> Dictionary:
	var r := Ink.rng(seed)
	var hair: String = ["low", "afro", "gele", "cap", "braids"][r.randi() % 5]
	var top: Color = ANKARA[r.randi() % ANKARA.size()] if r.randf() < 0.35 else SHIRTS[r.randi() % SHIRTS.size()]
	return {
		"skin": SKINS[r.randi() % SKINS.size()],
		"top": top,
		"bottom": top if hair == "gele" and r.randf() < 0.6 else TROUSERS[r.randi() % TROUSERS.size()],
		"hair": hair,
		"hair_col": ANKARA[r.randi() % ANKARA.size()] if hair == "gele" or hair == "cap" else Color("#151010"),
		"extra": "wrapper" if hair == "gele" else "",
	}


func step(delta: float, dir: Vector2, world: Layout.WorldData) -> void:
	var move := dir
	if move == Vector2.ZERO and target != Vector2.INF:
		var to := target - position
		if to.length() < 4.0:
			target = Vector2.INF
		else:
			move = to.normalized()
	velocity = move * speed
	if move != Vector2.ZERO:
		var next := position + velocity * delta
		if not world.is_blocked(next):
			position = next
		elif not world.is_blocked(Vector2(next.x, position.y)):
			position.x = next.x
		elif not world.is_blocked(Vector2(position.x, next.y)):
			position.y = next.y
		else:
			target = Vector2.INF
		if absf(move.x) > absf(move.y) * 1.1:
			facing = "side"
			flip = move.x < 0.0
		else:
			facing = "down" if move.y > 0.0 else "up"
		anim_t += delta * anim_fps
	else:
		anim_t = 0.0
	_update_sprite()
	# Moving the node is free; only re-draw when the pose actually changes (~anim_fps, not every frame).
	var key := "%s%s%d%s" % [facing, flip, int(anim_t) % 4, velocity.length() > 1.0]
	if key != _drawn_key:
		_drawn_key = key
		queue_redraw()


## Facing as a network code: 0 down, 1 up, 2 right, 3 left.
func facing_code() -> int:
	if facing == "side":
		return 3 if flip else 2
	return 1 if facing == "up" else 0


## Remote players: glide toward the latest server position (snapshots arrive ~10/s).
func follow(delta: float, tgt: Vector2, code: int) -> void:
	var to := tgt - position
	var d := to.length()
	if d > 320.0:
		position = tgt
		velocity = Vector2.ZERO
	elif d > 0.8:
		position = position.move_toward(tgt, maxf(speed * 1.6, d * 8.0) * delta)
		velocity = to.normalized() * speed
		anim_t += delta * anim_fps
	else:
		velocity = Vector2.ZERO
		anim_t = 0.0
	facing = ["down", "up", "side", "side"][clampi(code, 0, 3)]
	flip = code == 3
	_update_sprite()
	var key := "%s%s%d%s" % [facing, flip, int(anim_t) % 4, velocity.length() > 1.0]
	if key != _drawn_key:
		_drawn_key = key
		queue_redraw()


func _draw() -> void:
	var moving := velocity.length() > 1.0
	var phase := int(anim_t) % 4
	var swing: float = [0.0, 1.0, 0.0, -1.0][phase] if moving else 0.0
	var bob := -1.5 if moving and phase % 2 == 1 else 0.0
	var sx := -1.0 if flip and facing == "side" else 1.0
	var skin: Color = look.get("skin", SKINS[0])
	var top: Color = look.get("top", SHIRTS[0])
	var bottom: Color = look.get("bottom", TROUSERS[0])

	Ink.shadow(self, Vector2(2, 0), Vector2(11, 4), 0.35)
	if _spr:
		_draw_name()
		return
	# Legs.
	if look.get("extra", "") != "wrapper":
		var lx := [-4.5, 1.5]
		for i in 2:
			var off: float = swing * (2.5 if facing == "side" else 1.5) * (1.0 if i == 0 else -1.0)
			var x: float = lx[i] + (off if facing == "side" else 0.0)
			var lift: float = -2.0 if facing != "side" and ((i == 0 and swing > 0) or (i == 1 and swing < 0)) else 0.0
			Ink.rect(self, Rect2(x * sx - 1.5, -13 + lift, 5, 12), bottom, 1.6)
	else:
		Ink.poly(self, PackedVector2Array([Vector2(-9, -22 + bob), Vector2(9, -22 + bob), Vector2(10.5, -1), Vector2(-10.5, -1)]), bottom, 1.8)
	# Body.
	Ink.rect(self, Rect2(-8, -26 + bob, 16, 14), top, 1.8)
	if look.get("extra", "") == "towel":
		Ink.rect(self, Rect2((3 if facing != "side" else -2) * sx, -27 + bob, 5, 11), Color("#efe9da"), 1.2)
	# Arms with big hands.
	if facing != "side":
		for s in [-1.0, 1.0]:
			var a: float = swing * 1.5 * s
			Ink.rect(self, Rect2(s * 9.5 - 2.5, -24 + bob + a, 5, 10), top, 1.4)
			Ink.circle(self, Vector2(s * 9.5, -13 + bob + a), 2.8, skin, 1.2)
	else:
		Ink.rect(self, Rect2(-2.5 + swing * 2.5 * sx, -24 + bob, 5, 10), top, 1.4)
		Ink.circle(self, Vector2(swing * 2.5 * sx, -13 + bob), 2.8, skin, 1.2)
	# Big head.
	var hc := Vector2(0, -37 + bob)
	Ink.circle(self, hc, 10.5, skin, 2.0)
	var hair_col: Color = look.get("hair_col", Color.BLACK)
	match look.get("hair", "low"):
		"low":
			draw_arc(hc, 9.0, PI * 1.05 if facing != "up" else 0.0, PI * 1.95 if facing != "up" else TAU, 16, hair_col, 5.0)
		"afro":
			Ink.circle(self, hc + Vector2(0, -4 if facing != "up" else 0), 11.5 if facing != "up" else 12.5, hair_col, 1.8)
			if facing != "up":
				Ink.circle(self, hc + Vector2(0, 2.5), 8.5, skin, 0.0)
		"braids":
			draw_arc(hc, 9.5, PI, TAU, 16, hair_col, 5.0)
			for i in range(-2, 3):
				draw_line(hc + Vector2(i * 3.5, 0), hc + Vector2(i * 3.5, 12), hair_col, 2.0)
		"cap":
			Ink.poly(self, PackedVector2Array([hc + Vector2(-10, -3), hc + Vector2(10, -3), hc + Vector2(8, -11), hc + Vector2(-8, -11)]), hair_col, 1.6)
		"gele":
			Ink.ellipse(self, hc + Vector2(0, -8), Vector2(15, 8), hair_col, 1.8, -0.2)
			Ink.ellipse(self, hc + Vector2(7, -13), Vector2(7, 4.5), hair_col.lightened(0.2), 1.4, 0.5)
	# Face.
	if facing == "down":
		draw_circle(hc + Vector2(-3.8, 1.5), 1.6, Ink.COLOR)
		draw_circle(hc + Vector2(3.8, 1.5), 1.6, Ink.COLOR)
		draw_arc(hc + Vector2(0, 4.5), 2.6, 0.2, PI - 0.2, 8, Color(0.25, 0.1, 0.06), 1.2)
	elif facing == "side":
		draw_circle(hc + Vector2(5.0 * sx, 1.0), 1.6, Ink.COLOR)
	_draw_name()


func _draw_name() -> void:
	if display_name == "":
		return
	var font := ThemeDB.fallback_font
	var y := -SPRITE_H - 6.0 if _spr else -56.0
	draw_string_outline(font, Vector2(-60, y), display_name, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, 4, Ink.COLOR)
	draw_string(font, Vector2(-60, y), display_name, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, Color("#f1e6c8"))
