class_name AreaHeat
extends Node
## Area heat (M9 #3): fights, hard crashes, knocking people over and zooming past checkpoints
## build heat (0–5 stars). From two stars, Task Force vans come after you (two vans from four).
## Lose them: get out of sight and off the main road. Hiding in alleys or on foot cools you down
## fastest. Caught? Pay the fine, fight your way out, or (on foot) try to run.

const VAN_COLOUR := Color("#2f5e3a")

var host: StreetHost
var main: Node2D
var vans: Array = [] # {node, stuck_t, rev_t, last_pos, siren_t}
var _stun_t := 0.0
var _was_hot := false
var _rng := RandomNumberGenerator.new()


func setup(h: StreetHost) -> void:
	host = h
	main = h.main
	_rng.randomize()


func target() -> Node2D:
	return main.danfo if main.mode == "driving" else main.player


func tick(dt: float) -> void:
	if host.story_busy():
		_clear_vans()
		return
	var st := Street.stars()
	var want := 0 if st < 2 else (1 if st < 4 else 2)
	while vans.size() < want:
		if not _spawn_van():
			break
	while vans.size() > want:
		var v: Dictionary = vans.pop_back()
		(v["node"] as Node).queue_free()
	_stun_t = maxf(0.0, _stun_t - dt)
	var tgt := target()
	var seen := false
	for v: Dictionary in vans:
		var n: Node2D = v["node"]
		var to: Vector2 = tgt.position - n.position
		var dist := to.length()
		if dist < 950.0:
			seen = true
		if dist > 2800.0 or float(v["stuck_t"]) > 6.0:
			_place_van(v)
			continue
		var inp := Vector2.ZERO if _stun_t > 0.0 else to.normalized()
		if float(v["rev_t"]) > 0.0:
			v["rev_t"] = float(v["rev_t"]) - dt
			inp = -Vector2.from_angle(n.heading)
		n.drive(dt, inp, main.map)
		var moved: float = n.position.distance_to(v["last_pos"])
		v["last_pos"] = n.position
		if absf(n.speed) < 25.0 and inp != Vector2.ZERO and moved < 0.5:
			v["stuck_t"] = float(v["stuck_t"]) + dt
			if float(v["stuck_t"]) > 1.2 and float(v["rev_t"]) <= 0.0:
				v["rev_t"] = 0.8
		else:
			v["stuck_t"] = 0.0
		v["siren_t"] = float(v["siren_t"]) - dt
		if float(v["siren_t"]) <= 0.0 and dist < 1400.0:
			v["siren_t"] = 1.6
			Sound.sfx("siren", 1.0 + _rng.randf_range(-0.05, 0.05))
		n.queue_redraw()
		var slow: bool = main.mode != "driving" or absf(main.danfo.speed) < 90.0
		if _stun_t <= 0.0 and dist < (100.0 if main.mode == "driving" else 70.0) and slow:
			_caught()
			return
	# Cooling down: nobody in sight. Hiding off the main roads (alleys, on foot) is fastest.
	if not seen and Street.heat > 0.0:
		var surf: int = main.map.surface_at(tgt.position)
		var hidden: bool = main.mode == "walking" or not main.map.is_roadlike(surf)
		Street.heat = maxf(0.0, Street.heat - dt * (0.12 if hidden else 0.035))
		Street.changed.emit()
	if Street.heat >= 2.0:
		_was_hot = true
	elif _was_hot and Street.heat < 1.0:
		_was_hot = false
		Street.count("heat_escaped")
		main.hud.toast("You don lose them. Area heat cooling.")


func _spawn_van() -> bool:
	var n: Node2D = preload("res://actors/danfo.gd").new()
	n.set_kind("car", VAN_COLOUR)
	n.max_road = 395.0 # a touch faster than the danfo: you can't simply outrun them on a straight
	n.material = main.painted_mat
	var lights := _Lights.new()
	n.add_child(lights)
	main.streamer.add_child(n)
	var v := { "node": n, "stuck_t": 0.0, "rev_t": 0.0, "last_pos": Vector2.ZERO, "siren_t": 0.0 }
	vans.append(v)
	_place_van(v)
	main.hud.toast(host.pick(Street.db["taskforce_lines"]))
	return true


## Put a van on a road about 1,200 px from you, out of view.
func _place_van(v: Dictionary) -> void:
	var tgt := target().position
	var best: Vector2 = tgt + Vector2(1200, 0)
	var bd := INF
	for id in main.map.road_nodes:
		var p: Vector2 = main.map.road_nodes[id]
		var d := absf(p.distance_to(tgt) - 1200.0)
		if d < bd:
			bd = d
			best = p
	var n: Node2D = v["node"]
	n.position = best
	n.heading = (tgt - best).angle()
	n.speed = 0.0
	v["stuck_t"] = 0.0
	v["last_pos"] = best


func _clear_vans() -> void:
	for v: Dictionary in vans:
		(v["node"] as Node).queue_free()
	vans.clear()


func _caught() -> void:
	_stun_t = 999.0 # nobody moves while the card is up
	if main.mode == "driving":
		main.danfo.speed = 0.0
	var st := maxi(1, Street.stars())
	var fine := int(2000 * st * Street.price_k())
	var opts := [["pay", "Pay ₦%s" % Life.fmt_naira(fine), Life.can_afford(fine)], ["fight", "Fight them"]]
	if main.mode == "walking":
		opts.append(["run", "Run!"])
	var choice := await host.ask("Task Force!", "\"You fit the description. Come here!\"", opts)
	match choice:
		"pay":
			Life.spend(fine, "Task Force fine")
			Street.heat = 0.0
			main.hud.toast("You paid. They let you go… this time.")
		"run":
			if _rng.randf() < 0.5:
				_stun_t = 4.0
				main.hud.toast("You slipped away! Run, run!")
				return
			main.hud.toast("They caught your shirt. Fine doubled!")
			if Life.spend(fine * 2, "Task Force fine"):
				Street.heat = 0.0
			else:
				host.impound("Task Force: no money for the fine")
				Street.heat = 0.0
		"fight":
			var res: Dictionary = await main.story.story_minigame("fight", { "opponent": "Task Force", "intro": "Three of them. One of you. Na today!", "opponent_sprite": ["characters/officials-a.png", 2 + randi() % 2] })
			if int(res.get("score", 0)) > 55:
				Street.add_heat(-2.0)
				Street.add_rep(3.0)
				Street.count("fights_won")
				_stun_t = 8.0
				main.hud.toast("You fought off the Task Force! They're picking up their caps.", true)
				Street.post_gist("fight", "%s fought off the Task Force in %s!" % [Street._me(), main._district])
				return
			main.hud.toast("They beat you and towed the bus.")
			Life.restore("energy", -20.0)
			Life.spend(mini(Life.money, 3000), "Task Force \"fine\"")
			host.impound("lost a fight with the Task Force")
			Street.heat = 0.0
	_stun_t = 3.0
	Street.changed.emit()


## Flashing roof lights and the "TASK FORCE" lettering on a van.
class _Lights extends Node2D:
	func _ready() -> void:
		z_index = 2

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var on := int(Time.get_ticks_msec() / 180) % 2 == 0
		draw_circle(Vector2(-6, -22), 6.0, Color(1, 0.15, 0.1, 0.95 if on else 0.3))
		draw_circle(Vector2(6, -22), 6.0, Color(0.2, 0.4, 1, 0.3 if on else 0.95))
		var font := ThemeDB.fallback_font
		draw_string_outline(font, Vector2(-34, -34), "TASK FORCE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color("#1d1611"))
		draw_string(font, Vector2(-34, -34), "TASK FORCE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#f1e6c8"))
