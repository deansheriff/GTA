class_name Chase
extends RefCounted
## Story chases (1.3 on foot, 1.4 in the danfo): the Chief's men follow the hero along nav paths.
## Staying close fills "heat"; full heat = caught. In the danfo, passengers vote on turns: a lucky
## vote stalls the chasers (Pepper and Salt start arguing about jollof), an unlucky one adds heat.

const VehicleScript := preload("res://actors/danfo.gd")
const NpcScript := preload("res://actors/story_npc.gd")

var map: MapData
var nav: Nav
var parent: Node2D
var mat: Material
var on := "danfo"
var chasers: Array = [] # [{node, path, repath_t, stall_t}]
var heat := 0.0
var caught := false
var active := false
var vote_t := 0.0
var votes := false
var _rng := RandomNumberGenerator.new()


func setup(m: MapData, n: Nav, p: Node2D, material: Material) -> void:
	map = m
	nav = n
	parent = p
	mat = material


func start(s: Dictionary, focus: Vector2, heading: float, existing: Dictionary) -> void:
	stop()
	_rng.randomize()
	active = true
	on = s.get("on", "danfo")
	votes = s.get("votes", false)
	vote_t = 12.0
	heat = 0.0
	caught = false
	var ids: Array = s.get("chasers", ["pepper"])
	for i in ids.size():
		var id: String = ids[i]
		var node: Node2D
		if on == "foot":
			node = existing.get(id, null)
			if node == null:
				node = NpcScript.new()
				node.setup(id, id)
				node.material = mat
				parent.add_child(node)
				node.position = focus - Vector2.from_angle(heading) * (260.0 + i * 80.0)
		else:
			node = VehicleScript.new()
			node.set_kind("car", Color("#7a1f1a") if i == 0 else Color("#d9d3c4"))
			node.material = mat
			node.max_road = 345.0 # a little slower than Baba God Dey on the straights
			parent.add_child(node)
			var back := focus - Vector2.from_angle(heading) * (520.0 + i * 180.0)
			node.position = back if not map.is_blocked(back) else focus + Vector2(0, 600 + i * 180)
			node.heading = heading
		chasers.append({ "node": node, "path": PackedVector2Array(), "repath_t": 0.0, "stall_t": 0.0, "id": id, "spawned": on != "foot" or not existing.has(id) })


func stop() -> void:
	for c in chasers:
		if c["spawned"] and is_instance_valid(c["node"]):
			(c["node"] as Node).queue_free()
	chasers.clear()
	active = false


## Returns a vote prompt dictionary when the passengers want a say (danfo chases only).
func tick(dt: float, focus: Vector2) -> Dictionary:
	if not active:
		return {}
	var near := false
	for c in chasers:
		var node: Node2D = c["node"]
		if not is_instance_valid(node):
			continue
		c["stall_t"] = maxf(0.0, float(c["stall_t"]) - dt)
		c["repath_t"] = float(c["repath_t"]) - dt
		if float(c["repath_t"]) <= 0.0:
			c["repath_t"] = 0.8
			c["path"] = nav.walk_path(node.position, focus) if on == "foot" else nav.drive_path(node.position, focus)
		var path: PackedVector2Array = c["path"]
		while path.size() > 1 and node.position.distance_to(path[0]) < 70.0:
			path.remove_at(0)
		var goal: Vector2 = path[0] if path.size() > 0 else focus
		if node.position.distance_to(focus) < 260.0:
			goal = focus
		if on == "foot":
			if float(c["stall_t"]) <= 0.0:
				node.chase_step(dt, goal, map)
		else:
			var inp := Vector2.ZERO if float(c["stall_t"]) > 0.0 else (goal - node.position).normalized()
			node.drive(dt, inp, map)
		var d := node.position.distance_to(focus)
		if d < (90.0 if on == "foot" else 230.0):
			near = true
	heat = clampf(heat + (dt / (1.6 if on == "foot" else 3.5) if near else -dt / 7.0), 0.0, 1.0)
	if heat >= 1.0:
		caught = true
	if votes:
		vote_t -= dt
		if vote_t <= 0.0:
			vote_t = 15.0
			return Story.chats.get("votes", [{ "q": "Which way?", "a": "Left", "b": "Right" }]).pick_random()
	return {}


## Apply a passenger vote. Returns the line to show.
func resolve_vote(pick: int) -> String:
	if _rng.randf() < 0.65:
		for c in chasers:
			c["stall_t"] = 3.5
		heat = maxf(0.0, heat - 0.25)
		return ["Pepper and Salt stop to argue about whose jollof is better!", "Shortcut dey! (For once, there really was one.)", "The chasers got stuck behind a wedding convoy!"][_rng.randi() % 3]
	heat = minf(1.0, heat + 0.15)
	return ["Wrong turn! A goat is blocking the road.", "Dead end! The prophetess's \"turn of favour\" was not favourable."][_rng.randi() % 2] if pick == 0 else "Main road go-slow! They're gaining!"


func state() -> Dictionary:
	return { "heat": heat, "caught": caught }
