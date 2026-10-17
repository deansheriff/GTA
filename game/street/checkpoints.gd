class_name Checkpoints
extends Node
## Road checkpoints (M9 #2). Now and then a barrier goes up on the road ahead: Road Marshals,
## Motor Park Union boys (agberos) collecting "owo ticket", or the Area Task Force when your heat
## is up. Stop and choose:
##   Roger them (pay), argue (charisma and reputation decide; lose and the fine doubles, and you
##   can't pay it, the bus goes to the yard), or zoom past (Area heat; agberos throw things).
## Tunde's Blood Pressure rises with every one of them.

var host: StreetHost
var main: Node2D
var active := {} # {kind, pos, heading, node, npcs, state}
var _cd := 45.0
var _rng := RandomNumberGenerator.new()


func setup(h: StreetHost) -> void:
	host = h
	main = h.main
	_rng.randomize()


func tick(dt: float) -> void:
	if host.story_busy() or Street.impounded:
		clear()
		return
	_cd -= dt
	var d: Node2D = main.danfo
	if active.is_empty():
		if _cd <= 0.0 and main.mode == "driving" and absf(d.speed) > 80.0:
			_cd = _rng.randf_range(80.0, 160.0)
			_spawn()
		return
	var dist := d.position.distance_to(active["pos"])
	if dist > 2600.0 and active["state"] != "stopped":
		clear()
		return
	if active["state"] == "waiting" and main.mode == "driving" and dist < 200.0:
		active["state"] = "stopped"
		_stop()


func clear() -> void:
	if active.is_empty():
		return
	for n: Node in active["npcs"]:
		n.queue_free()
	(active["node"] as Node).queue_free()
	active = {}


## Demo/tests: a checkpoint `dist` px ahead of the bus.
func spawn_ahead(dist: float, kind: String) -> void:
	clear()
	var d: Node2D = main.danfo
	_place(d.position + Vector2.from_angle(d.heading) * dist, kind)


func _spawn() -> void:
	var d: Node2D = main.danfo
	var fwd := Vector2.from_angle(d.heading)
	var best := ""
	var bd := INF
	for id in main.map.road_nodes:
		var p: Vector2 = main.map.road_nodes[id]
		var to := p - d.position
		var dist := to.length()
		if dist < 700.0 or dist > 1500.0 or to.normalized().dot(fwd) < 0.8:
			continue
		if dist < bd:
			bd = dist
			best = id
	if best == "":
		return
	var kind := "marshal"
	if Street.heat >= 1.0 and _rng.randf() < 0.6:
		kind = "task"
	elif not main.jobs.active.is_empty() and main.jobs.active.get("type") == "danfo" and _rng.randf() < 0.6:
		kind = "agbero"
	elif _rng.randf() < 0.3:
		kind = "agbero"
	_place(main.map.road_nodes[best], kind)


func _place(pos: Vector2, kind: String) -> void:
	var d: Node2D = main.danfo
	var node := _Barrier.new()
	node.position = pos
	node.heading = (pos - d.position).angle() + PI / 2.0
	node.kind = kind
	node.material = main.painted_mat
	main.streamer.add_child(node)
	var npcs := []
	var who: String = { "marshal": "marshal", "agbero": "agbero", "task": "taskforce" }[kind]
	for i in 2:
		var n: Node2D = preload("res://actors/story_npc.gd").new()
		n.setup(who, who)
		n.material = main.painted_mat
		n.position = pos + Vector2.from_angle(node.heading) * (i * 2 - 1) * 95.0 + Vector2(0, 20)
		main.streamer.add_child(n)
		npcs.append(n)
	active = { "kind": kind, "pos": pos, "node": node, "npcs": npcs, "state": "waiting" }
	host.radio.report_checkpoint(kind, pos)


func _info() -> Dictionary:
	return Street.db["checkpoints"][active["kind"]]


func _stop() -> void:
	var d: Node2D = main.danfo
	d.speed = 0.0
	var info := _info()
	var lines: Array = info["lines"]
	var line: String = lines[_rng.randi() % lines.size()]
	(active["npcs"][0] as Node2D).say(line, 4.0)
	var roger := int(ceil(int(info["roger"]) * Street.price_k()))
	if Street.current.get("stolen", false):
		# They know the car isn't yours: everything costs three times as much.
		roger *= 3
		line = "This motor no be your own! Where the papers?"
		(active["npcs"][0] as Node2D).say(line, 4.0)
	var choice := await host.ask("%s checkpoint" % info["name"], "\"%s\"" % line, [
		["roger", "Roger them (₦%s)" % Life.fmt_naira(roger), Life.can_afford(roger)],
		["argue", "Argue"],
		["zoom", "Zoom past"],
	])
	if active.is_empty():
		return
	_bp(6.0)
	match choice:
		"roger":
			Life.spend(roger, "Checkpoint \"settlement\"")
			Street.count("rogered")
			if active["kind"] == "agbero":
				Street.count("agbero_paid")
			(active["npcs"][0] as Node2D).say("Oya go. Drive well.", 3.0)
			main.hud.toast("You rogered them. ₦%s gone." % Life.fmt_naira(roger))
		"argue":
			await _argue(roger)
		"zoom":
			var add: float = { "marshal": 1.5, "agbero": 0.7, "task": 2.0 }[active["kind"]]
			Street.add_heat(add)
			Street.add_rep(-2.0)
			if active["kind"] == "agbero":
				host.care.hit(200.0, d.position)
				main.hud.toast("You zoomed past! The agberos threw stones at the bus.")
			else:
				main.hud.toast("You zoomed past the %s! Area heat up." % info["name"])
				Sound.sfx("siren")
			Street.post_gist("zoom", "%s zoomed past a %s checkpoint!" % [Street._me(), info["name"]])
	_leave()


func _argue(roger: int) -> void:
	var info := _info()
	var chance := 0.3 + Life.level("charisma") * 0.05 + Street.rep / 300.0
	if Life.hero == "ngozi":
		chance += float(Life.stats.get("aura", 40.0)) / 400.0
	chance = clampf(chance, 0.1, 0.85)
	if _rng.randf() < chance:
		Street.count("argued_free")
		Street.add_rep(1.0)
		Life.add_xp("charisma", 15)
		(active["npcs"][0] as Node2D).say("Okay, okay. Go. You get mouth o.", 3.0)
		main.hud.toast("You argued your way through. Free!")
		return
	_bp(14.0)
	var fine := int(ceil(int(info["fine"]) * Street.price_k()))
	(active["npcs"][0] as Node2D).say("You dey argue? Na ₦%s now!" % Life.fmt_naira(fine), 4.0)
	if Life.spend(fine, "Checkpoint fine"):
		main.hud.toast("Argument lost. Fine: ₦%s." % Life.fmt_naira(fine))
	else:
		host.impound("you couldn't pay a checkpoint fine")


func _leave() -> void:
	if active.is_empty():
		return
	active["state"] = "done"
	var keep: Dictionary = active
	await get_tree().create_timer(6.0).timeout
	if active == keep:
		clear()


func _bp(amount: float) -> void:
	if Life.hero == "tunde":
		Life.stats["bp"] = minf(100.0, float(Life.stats.get("bp", 20.0)) + amount)


## The barrier across the road: striped pole, cones and a sign.
class _Barrier extends Node2D:
	var heading := 0.0
	var kind := "marshal"

	func _draw() -> void:
		var dir := Vector2.from_angle(heading)
		var a := -dir * 80.0
		var b := dir * 80.0
		draw_line(a + Vector2(0, 6), b + Vector2(0, 6), Color(0, 0, 0, 0.25), 9.0)
		for i in 8:
			var p0 := a.lerp(b, i / 8.0)
			var p1 := a.lerp(b, (i + 1) / 8.0)
			draw_line(p0, p1, Color("#c8432f") if i % 2 == 0 else Color("#f1e6c8"), 7.0)
		for p: Vector2 in [a, b]:
			draw_colored_polygon(PackedVector2Array([p + Vector2(-8, 8), p + Vector2(8, 8), p + Vector2(0, -12)]), Color("#e86a1c"))
		var font := ThemeDB.fallback_font
		var label: String = { "marshal": "ROAD MARSHALS", "agbero": "OWO TICKET", "task": "TASK FORCE" }[kind]
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_rect(Rect2(Vector2(-w * 0.5 - 6, -40), Vector2(w + 12, 20)), Color("#1d1611"))
		draw_string(font, Vector2(-w * 0.5, -25), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#e0a91c"))
