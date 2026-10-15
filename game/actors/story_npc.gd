extends Node2D
## A named story character standing in the world or an interior: painted cast sprite (or a
## townsperson), name plate, idle bob, speech bubble, The Stare freeze, and simple chasing.

const INK := Color("#1d1611")
const PAPER := Color("#f1e6c8")
const SPRITE_H := 64.0

var npc_id := ""
var who := ""
var display_name := ""
var colour := Color("#e0a91c")
var frozen_t := 0.0
var speed := 135.0
var velocity := Vector2.ZERO
var _spr: Sprite2D
var _t := 0.0
var _bubble := ""
var _bubble_t := 0.0
var _base_y := 0.0
var _last_key := ""


func setup(id: String, who_id: String) -> void:
	npc_id = id
	who = who_id
	var info := Story.who(who_id)
	display_name = String(info.get("name", who_id))
	colour = Color(String(info.get("colour", "#e0a91c")))
	var path := ""
	var frame := 0
	if info.has("sprites"):
		# A role with several looks (drivers, marshals, agberos…): a different one each time.
		var pick: Array = info["sprites"][randi() % (info["sprites"] as Array).size()]
		path = pick[0]
		frame = int(pick[1])
	elif info.has("sprite"):
		path = info["sprite"][0]
		frame = int(info["sprite"][1])
	else:
		var i := int(info.get("ped", 0))
		path = "characters/pedestrians-a.png" if i < 8 else "characters/pedestrians-b.png"
		frame = i % 8
	use_sprite(path, frame)


## Show this NPC as `frame` of a painted character sheet.
func use_sprite(path: String, frame: int) -> void:
	if _spr:
		_spr.queue_free()
		_spr = null
	var t := Art.tex(path)
	var sheet := Art.sheet_info(path)
	if t and not sheet.is_empty():
		_spr = Sprite2D.new()
		_spr.texture = t
		_spr.hframes = int(sheet["cols"])
		_spr.vframes = int(sheet["rows"])
		_spr.frame = frame
		var sc := SPRITE_H / float(sheet["frameH"])
		_spr.scale = Vector2(sc, sc)
		_base_y = -(float(sheet["frameH"]) * 0.5 - 2.0) * sc
		_spr.position = Vector2(0, _base_y)
		add_child(_spr)


func say(text: String, seconds := 3.0) -> void:
	_bubble = text
	_bubble_t = seconds
	queue_redraw()


func freeze(seconds: float) -> void:
	frozen_t = seconds
	say("?! …", seconds)


## Step toward a goal (used by foot chases). Slides along walls like the player does.
func chase_step(delta: float, goal: Vector2, world: MapData) -> void:
	if frozen_t > 0.0:
		velocity = Vector2.ZERO
		return
	var to := goal - position
	if to.length() < 2.0:
		velocity = Vector2.ZERO
		return
	velocity = to.normalized() * speed
	var next := position + velocity * delta
	if world == null or not world.is_blocked(next):
		position = next
	elif not world.is_blocked(Vector2(next.x, position.y)):
		position.x = next.x
	elif not world.is_blocked(Vector2(position.x, next.y)):
		position.y = next.y
	if _spr and absf(velocity.x) > 1.0:
		_spr.flip_h = velocity.x < 0.0


func _process(delta: float) -> void:
	_t += delta
	if frozen_t > 0.0:
		frozen_t -= delta
	if _bubble_t > 0.0:
		_bubble_t -= delta
		if _bubble_t <= 0.0:
			_bubble = ""
			queue_redraw()
	if _spr:
		var moving := velocity.length() > 1.0
		var bob := absf(sin(_t * (9.0 if moving else 2.0))) * (3.0 if moving else 1.2)
		if frozen_t > 0.0:
			bob = 0.0
			_spr.position.x = sin(_t * 40.0) * 1.2 # trembling under The Stare
		else:
			_spr.position.x = 0.0
		_spr.position.y = _base_y - bob


func _draw() -> void:
	Ink.shadow(self, Vector2(2, 0), Vector2(13, 5), 0.35)
	var font := ThemeDB.fallback_font
	var y := -SPRITE_H - 8.0
	draw_string_outline(font, Vector2(-80, y), display_name, HORIZONTAL_ALIGNMENT_CENTER, 160, 14, 5, INK)
	draw_string(font, Vector2(-80, y), display_name, HORIZONTAL_ALIGNMENT_CENTER, 160, 14, colour.lightened(0.3))
	draw_circle(Vector2(0, y - 22), 6.0, Color("#e0a91c"))
	draw_arc(Vector2(0, y - 22), 6.0, 0, TAU, 14, INK, 2.0)
	if _bubble != "":
		var w := clampf(_bubble.length() * 8.0 + 24.0, 60.0, 260.0)
		var r := Rect2(-w * 0.5, y - 66, w, 34)
		draw_rect(r, PAPER)
		draw_rect(r, INK, false, 2.5)
		draw_string(font, Vector2(r.position.x + 8, r.position.y + 23), _bubble, HORIZONTAL_ALIGNMENT_CENTER, w - 16, 15, INK)
