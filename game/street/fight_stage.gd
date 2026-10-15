class_name FightStage
extends Node
## Fights you can watch (owner feedback: "I don't get to see the fights"). While the fist-fight
## buttons sit in a small panel at the bottom, the fight plays out in the street:
##  - the camera closes in on the two fighters, squared up face to face, crowd in a ring,
##  - every exchange is acted out: your jab lands (lunge, knock-back, "POW!"), a duck sways under
##    the swing, a block stops the slap, a miss gets you slapped,
##  - the loser goes down at the end and the winner celebrates.
## Slapstick only (Story Bible): no blood.

var host: StreetHost
var main: Node2D
var me: Node2D
var them: Node2D
var _spawned := false
var _cam: Camera2D
var _me_home := Vector2.ZERO
var _them_home := Vector2.ZERO
var _me_was_visible := true
var _active := false


func setup(h: StreetHost) -> void:
	host = h
	main = h.main


## Called by StoryHost before a fight starts. params.opponent_node: who you're fighting, if they
## exist in the world (an angry driver, another player); otherwise a stand-in steps up.
func begin(params: Dictionary) -> void:
	if _active or main.story.interior.active:
		return
	_active = true
	me = main.player
	_me_was_visible = me.visible
	if main.mode == "driving":
		# Out of the bus for the fight (the bus waits right there).
		me.position = main.danfo.position + Vector2.from_angle(main.danfo.heading + PI / 2.0) * 70.0
	me.visible = true
	var opp: Variant = params.get("opponent_node")
	if opp is Node2D and is_instance_valid(opp):
		them = opp
		_spawned = false
	else:
		them = preload("res://actors/walker.gd").new()
		them.use_pedestrian(randi() % 16)
		them.display_name = String(params.get("opponent", ""))
		them.material = main.painted_mat
		main.streamer.add_child(them)
		_spawned = true
	# Square up on open ground (not behind a kiosk or a wall): face to face, a short step apart.
	var ring := _open_ground(me.position)
	me.position = ring - Vector2(36, 0)
	them.position = ring + Vector2(36, 0)
	_me_home = me.position
	_them_home = them.position
	_face()
	# Close in: a fight camera between the two.
	_cam = Camera2D.new()
	# Frame the fighters in the upper part of the screen: the buttons sit along the bottom.
	_cam.position = (me.position + them.position) * 0.5 + Vector2(0, 36)
	_cam.zoom = main.get_viewport().get_camera_2d().zoom
	main.add_child(_cam)
	_cam.make_current()
	var tw := create_tween()
	tw.tween_property(_cam, "zoom", Vector2(1.9, 1.9), 0.6).set_trans(Tween.TRANS_SINE)
	host.reactions.crowd_to((me.position + them.position) * 0.5, 30.0)
	host.fx.pop("FIGHT!", _cam.position + Vector2(0, -60), Color("#ff7a5c"), 46, 1.0)


## The nearest spot with room for a fight and its crowd: no buildings or props within reach,
## and nothing tall standing just below it (things lower on screen are drawn over the fighters).
func _open_ground(near: Vector2) -> Vector2:
	var m: MapData = main.map
	for r: float in [0.0, 80.0, 160.0, 240.0, 320.0, 420.0, 560.0, 720.0]:
		for i in (1 if r == 0.0 else 12):
			var c := near + Vector2.from_angle(i * TAU / 12.0) * r
			var ok := true
			# Props and buildings are painted much bigger than their collision, so keep a wide berth:
			# a grid from 140 px left/right, 120 px above and 170 px below (things below draw on top).
			for gy in range(-120, 171, 40):
				for gx in range(-140, 141, 40):
					if m.is_blocked(c + Vector2(gx, gy)):
						ok = false
						break
				if not ok:
					break
			if ok:
				return c
	return near


func _face() -> void:
	if me.get("flip") != null:
		me.facing = "side"
		me.flip = them.position.x < me.position.x
		me.queue_redraw()
	if them.get("flip") != null:
		them.facing = "side"
		them.flip = me.position.x < them.position.x
		them.queue_redraw()
	elif them.has_method("say"):
		pass


## One exchange from the fist-fight mini-game: "hit", "duck", "block" or "ouch".
func exchange(kind: String, _move: String) -> void:
	if not _active:
		return
	var toward := (them.position - me.position).normalized()
	var head_me := me.position + Vector2(0, -70)
	var head_them := them.position + Vector2(0, -70)
	match kind:
		"hit":
			_lunge(me, toward * 22.0)
			_knock(them, toward * 16.0)
			host.fx.pop(["POW!", "GBOSA!", "KPAK!", "BAM!"][randi() % 4], head_them, Color("#e0a91c"), 34, 0.7)
			Sound.sfx("punch", randf_range(0.9, 1.1))
		"duck":
			_lunge(them, -toward * 22.0)
			_duck(me)
			host.fx.pop("WHOOSH", head_me + Vector2(0, -10), Color("#9fd38a"), 26, 0.6)
			Sound.sfx("whoosh", 1.3)
		"block":
			_lunge(them, -toward * 18.0)
			_knock(me, -toward * 5.0)
			host.fx.pop("BLOCK!", head_me, Color("#9fc4cf"), 28, 0.6)
			Sound.sfx("tap", 0.7)
		_:
			_lunge(them, -toward * 22.0)
			_knock(me, -toward * 16.0)
			host.fx.pop(["SLAP!", "OUCH!", "GBAM!"][randi() % 3], head_me, Color("#ff7a5c"), 34, 0.7)
			Sound.sfx("punch", randf_range(0.75, 0.9))
			if not Settings.get_value("reduced_motion", false):
				var tw := create_tween()
				for i in 4:
					tw.tween_property(_cam, "offset", Vector2(randf_range(-5, 5), randf_range(-5, 5)), 0.03)
				tw.tween_property(_cam, "offset", Vector2.ZERO, 0.03)


func _lunge(n: Node2D, by: Vector2) -> void:
	var home := _me_home if n == me else _them_home
	var tw := create_tween()
	tw.tween_property(n, "position", home + by, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "position", home, 0.14)


func _knock(n: Node2D, by: Vector2) -> void:
	var home := _me_home if n == me else _them_home
	var tw := create_tween()
	tw.tween_interval(0.07)
	tw.tween_property(n, "position", home + by, 0.06)
	tw.parallel().tween_property(n, "modulate", Color(1.6, 1.4, 1.4), 0.06)
	tw.parallel().tween_property(n, "rotation", signf(by.x) * 0.18, 0.06)
	tw.tween_property(n, "position", home, 0.2)
	tw.parallel().tween_property(n, "modulate", Color.WHITE, 0.2)
	tw.parallel().tween_property(n, "rotation", 0.0, 0.2)


func _duck(n: Node2D) -> void:
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector2(1.1, 0.75), 0.08)
	tw.tween_property(n, "scale", Vector2.ONE, 0.18)


## The fight is over: the loser goes down, the winner celebrates, then everything goes back.
func finish(result: Dictionary) -> void:
	if not _active:
		return
	var score := int(result.get("score", 0))
	var won := score > 50
	var draw := score == 50
	var loser: Node2D = them if won else me
	var winner: Node2D = me if won else them
	if not draw:
		var tw := create_tween()
		tw.tween_property(loser, "rotation", (PI / 2.0) * (1.0 if loser.position.x > winner.position.x else -1.0), 0.25).set_trans(Tween.TRANS_BOUNCE)
		var hop := create_tween()
		hop.tween_property(winner, "position", winner.position + Vector2(0, -14), 0.12)
		hop.tween_property(winner, "position", winner.position, 0.12)
		host.fx.pop("K.O.!" if score >= 80 or score <= 20 else ("WINS!" if won else "DOWN!"), loser.position + Vector2(0, -60), Color("#e0a91c"), 40, 1.4)
		Sound.sfx("crash", 0.7)
	await get_tree().create_timer(1.6).timeout
	me.rotation = 0.0
	if is_instance_valid(them):
		them.rotation = 0.0
	if main.mode == "driving":
		me.visible = false
		me.position = main.danfo.position
	var tw2 := create_tween()
	tw2.tween_property(_cam, "zoom", main.camera.zoom, 0.4)
	await tw2.finished
	main.camera.make_current()
	_cam.queue_free()
	if _spawned and is_instance_valid(them):
		them.queue_free()
	_active = false
