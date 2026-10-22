class_name Explore3D
extends Node3D
## Things to find between missions (D-032), Lagos only:
##  - Lagos Stories: 16 places with a story to tell (a gold ✦ over them when you're near). Read one
##    for a little Respect, money or something useful.
##  - Stashes: 12 sacks hidden behind buildings, away from the roads: cash, rounds, a jerrycan of
##    fuel, vehicle papers (they work at checkpoints), a charm.
##  - Street encounters that come to you: a pickpocket to chase, a stalled danfo to push, a market
##    woman's spilled oranges, two boys fighting to break up.
## What you've found is saved (FreeRoam3D.found); the Street life page counts it.

const STORIES := [
	{ "id": "tmb", "at": "node:tmb_mid", "off": [3, 0], "title": "Third Mainland Bridge", "text": "Nearly twelve kilometres of road on stilts across the lagoon. At night the go-slow lights it from end to end, and from the middle you can see Makoko's lamps on the water.", "money": 1000 },
	{ "id": "makoko", "at": "landmark:makoko-jetty", "off": [2, 2], "title": "Makoko", "text": "Families have fished from these stilts for generations. Here the canoe is the school bus, the market and the ambulance.", "respect": 1 },
	{ "id": "oshodi", "at": "landmark:oshodi-market", "off": [4, -3], "title": "Under the bridge", "text": "Oshodi never sleeps. On the third pillar, under fifteen years of posters, someone once scratched: \"CHIEF BAYO — UNION OF THE PEOPLE\".", "respect": 2 },
	{ "id": "ojuelegba", "at": "landmark:ojuelegba-buka", "off": [3, 3], "title": "Ojuelegba", "text": "Everybody in Lagos passes through Ojuelegba at least once a week. The buka's owner swears she has fed three governors and four armed robbers. Not on the same day.", "money": 1500 },
	{ "id": "badagry", "at": "landmark:badagry-church", "off": [5, 5], "title": "Badagry", "text": "One of the first places on this coast where people were taken onto the slave ships. The walk to the beach they call the Point of No Return is quiet. Nobody hurries it.", "respect": 2 },
	{ "id": "seme", "at": "landmark:seme-border", "off": [4, -4], "title": "Seme border", "text": "Rice, tyres, frozen chicken, petrol: everything has crossed here in somebody's boot. A customs man's cousin left a set of vehicle papers in the guard hut. They're yours now.", "item": "papers" },
	{ "id": "lekki_beach", "at": "node:lekki_beach", "off": [6, 6], "title": "The beach", "text": "On Sundays the whole of Lagos comes to the sea: horse rides, suya, a pastor baptising in the surf, and a football match with forty players a side.", "money": 1000 },
	{ "id": "computer_village", "at": "landmark:computer-village", "off": [-4, 4], "title": "Computer Village", "text": "If it has a chip in it, someone here can fix it, unlock it or sell you two. Bigz learned everything he knows in these stalls before he was fifteen.", "respect": 1 },
	{ "id": "alaba", "at": "landmark:alaba-market", "off": [-5, 4], "title": "Alaba International", "text": "Every second stall has a sticker: \"OKPU ELECTRONICS: E NO DEY SPOIL\". The traders call him Ọkpụ and lower their voices when they say it.", "respect": 1 },
	{ "id": "yaba", "at": "landmark:yaba-barbershop", "off": [3, -3], "title": "Yaba", "text": "Students, coders, and the oldest barbershop gossip in Lagos. The barber says Sabi's father cut his hair here every Friday. \"Always paid. Always tipped.\"", "money": 2000 },
	{ "id": "obalende", "at": "landmark:obalende-motor-park", "off": [4, 4], "title": "Obalende", "text": "\"Obalende! Obalende!\" The cry every danfo conductor learns first. A conductor here gives you half a box of rounds he \"found\". Don't ask.", "ammo": 24 },
	{ "id": "home", "at": "landmark:balogun-compound", "off": [-3, 3], "title": "Papa's chair", "text": "Behind the house, under a tarpaulin, the wooden chair Chief Bayo sat in every evening. Mama Àgbà never let anyone throw it away.", "respect": 2 },
	{ "id": "radio", "at": "landmark:radio-gbedu", "off": [4, 4], "title": "Radio Gbedu", "text": "The station started in a container with one microphone. The DJ still keeps that microphone in a glass box by the door.", "money": 1000 },
	{ "id": "luth", "at": "landmark:luth", "off": [-4, 4], "title": "LUTH", "text": "The hospital that has stitched up half of Lagos. In the waiting room, a mother tells you her son was born here the night of the big flood, in a corridor, by torchlight.", "respect": 1 },
	{ "id": "festac", "at": "node:festac_c", "off": [5, 5], "title": "Festac Town", "text": "Built for FESTAC '77, when artists from across the Black world came to Lagos. The old men at the corner still argue about which band played best.", "money": 1500 },
	{ "id": "ajegunle", "at": "node:ajegunle_c", "off": [4, 4], "title": "AJ City", "text": "Ajegunle: footballers, musicians and fighters, all from the same few streets. A painted wall lists their names; there's space left at the bottom.", "respect": 2 },
]
const STASH_LOOT := [
	{ "money": 5000, "text": "A plastic bag of naira notes, rolled tight." },
	{ "ammo": 24, "text": "A box of pistol rounds wrapped in a wrapper." },
	{ "item": "jerrycan", "text": "A full jerrycan of fuel. It fills your ride's tank the next time you need it." },
	{ "money": 8000, "text": "Somebody's emergency money in an old cocoa tin." },
	{ "item": "papers", "text": "A set of vehicle papers, stamped and complete. Checkpoints will accept them." },
	{ "respect": 2, "text": "A charm on a red string. People seem to give you more room." },
]

var world # Street3D
var _markers := {} # id -> Node3D
var _stashes: Array = [] # [{id, pos}]
var _enc := {} # the street encounter in progress
var _enc_t := 75.0
var _my_prompt := ""
var _rng := RandomNumberGenerator.new()
var _story_pos := {} # id -> Vector3


func setup(w) -> void:
	world = w
	_rng.seed = 17
	on_region()


func on_region() -> void:
	for id in _markers:
		if is_instance_valid(_markers[id]):
			(_markers[id] as Node).queue_free()
	_markers.clear()
	_stashes.clear()
	_story_pos.clear()
	_end_encounter(false)
	if world.region != "lagos":
		return
	for st: Dictionary in STORIES:
		_story_pos[st["id"]] = world.land_near(world.resolve({ "at": st["at"], "offset": st["off"] }))
	# Stashes: on bare ground behind buildings, well away from the roads, spread across the city.
	var map: MapData = world.map
	var r := RandomNumberGenerator.new()
	r.seed = 1212
	var tries := 0
	while _stashes.size() < 12 and tries < 4000:
		tries += 1
		var c := Vector2i(r.randi_range(2, map.cols - 3), r.randi_range(2, map.rows - 3))
		var i := c.y * map.cols + c.x
		if map.surface[i] != MapData.S.GROUND or map.blocked[i] == 1:
			continue
		var by_building := false
		var by_road := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = c + d
			if map.occupied[q.y * map.cols + q.x] == 1 and map.blocked[q.y * map.cols + q.x] == 1:
				by_building = true
			for k in range(1, 4):
				var q2: Vector2i = c + d * k
				if map.in_bounds(q2) and map.is_roadlike(map.surface[q2.y * map.cols + q2.x]):
					by_road = true
		if not by_building or by_road:
			continue
		var pos := Vector3((c.x + 0.5) * Terrain3D.CELL_M, 0, (c.y + 0.5) * Terrain3D.CELL_M)
		var spread := true
		for s: Dictionary in _stashes:
			if (s["pos"] as Vector3).distance_to(pos) < 120.0:
				spread = false
		if spread:
			_stashes.append({ "id": "stash%d" % _stashes.size(), "pos": pos })


func found_count() -> Array:
	var f: Dictionary = world.roam.found
	var st := STORIES.filter(func(s: Dictionary) -> bool: return f.has(s["id"])).size()
	var sh := _stashes.filter(func(s: Dictionary) -> bool: return f.has(s["id"])).size()
	return [st, STORIES.size(), sh, _stashes.size()]


func step(delta: float) -> void:
	if world.region != "lagos" or world.in_menu:
		return
	var busy: bool = world.missions.running != ""
	var f: Vector3 = world.focus()
	var on_foot: bool = world.ride == null
	var want_prompt := ""
	var want_cb := Callable()
	var want_at: Variant = null
	# Lagos Stories.
	for s: Dictionary in STORIES:
		var id := String(s["id"])
		if world.roam.found.has(id):
			continue
		var p: Vector3 = _story_pos.get(id, Vector3.ZERO)
		var d := Vector2(p.x - f.x, p.z - f.z).length()
		if d < 60.0 and not _markers.has(id):
			_markers[id] = _story_marker(p)
		elif d > 80.0 and _markers.has(id):
			(_markers[id] as Node).queue_free()
			_markers.erase(id)
		if d < 2.8 and on_foot and not busy:
			want_prompt = "READ: " + String(s["title"]).to_upper()
			want_cb = _read.bind(s)
			want_at = p + Vector3(0, 2.4, 0)
	# Stashes.
	for s: Dictionary in _stashes:
		var id := String(s["id"])
		if world.roam.found.has(id):
			continue
		var p: Vector3 = s["pos"]
		var d := Vector2(p.x - f.x, p.z - f.z).length()
		if d < 40.0 and not _markers.has(id):
			_markers[id] = _stash_marker(p)
		elif d > 55.0 and _markers.has(id):
			(_markers[id] as Node).queue_free()
			_markers.erase(id)
		if d < 2.2 and on_foot and not busy:
			want_prompt = "SEARCH"
			want_cb = _search.bind(s)
			want_at = p + Vector3(0, 1.2, 0)
	for id in _markers:
		var m: Node3D = _markers[id]
		if is_instance_valid(m) and m.get_child_count() > 1:
			(m.get_child(1) as Node3D).rotation.y += delta * 1.5
	# Street encounters.
	if not busy:
		_encounters(delta)
		if not _enc.is_empty() and String(_enc.get("prompt", "")) != "" and Vector2((_enc["pos"] as Vector3).x - f.x, (_enc["pos"] as Vector3).z - f.z).length() < 3.5 and on_foot:
			want_prompt = String(_enc["prompt"])
			want_cb = _enc_action
			want_at = (_enc["pos"] as Vector3) + Vector3(0, 2.6, 0)
	elif not _enc.is_empty():
		_end_encounter(false)
	# The prompt: ours if nobody else's.
	if want_prompt != "" and (world.prompt_text == "" or world.prompt_text == _my_prompt):
		world.prompt_text = want_prompt
		world.prompt_cb = want_cb
		world.prompt_at = want_at
		_my_prompt = want_prompt
	elif want_prompt == "" and _my_prompt != "" and world.prompt_text == _my_prompt:
		world.prompt_text = ""
		world.prompt_cb = Callable()
		_my_prompt = ""


func _story_marker(p: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = p
	add_child(root)
	var l := Label3D.new()
	l.text = "✦"
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 96
	l.pixel_size = 0.008
	l.modulate = Color("#f6d04d")
	l.outline_size = 8
	l.position.y = 2.2
	root.add_child(l)
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.7
	t.outer_radius = 0.78
	t.rings = 24
	t.ring_segments = 4
	ring.mesh = t
	var m := StandardMaterial3D.new()
	m.emission_enabled = true
	m.emission = Color("#f6d04d")
	m.emission_energy_multiplier = 2.0
	m.albedo_color = Color("#f6d04d")
	ring.material_override = m
	ring.position.y = 0.08
	root.add_child(ring)
	return root


func _stash_marker(p: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = p
	add_child(root)
	var sack := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.32
	sm.height = 0.5
	sm.radial_segments = 8
	sm.rings = 4
	sack.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#8a6a3a")
	m.roughness = 1.0
	sack.material_override = m
	sack.position.y = 0.22
	root.add_child(sack)
	# A faint glint you notice only up close.
	var glint := Label3D.new()
	glint.text = "·"
	glint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	glint.font_size = 96
	glint.pixel_size = 0.006
	glint.modulate = Color(1, 1, 1, 0.8)
	glint.position.y = 0.9
	glint.visibility_range_end = 12.0
	root.add_child(glint)
	Blob3D.add(root, Vector2(0.9, 0.9))
	return root


func _read(s: Dictionary) -> void:
	world.roam.found[String(s["id"])] = true
	if _markers.has(s["id"]):
		(_markers[s["id"]] as Node).queue_free()
		_markers.erase(s["id"])
	Sound.sfx("find")
	await world.say([{ "who": "story", "text": "%s. %s" % [String(s["title"]), String(s["text"])] }])
	_reward(s)
	var c := found_count()
	world.notify("Lagos Stories: %d of %d found." % [c[0], c[1]])
	world._save_game()


func _search(s: Dictionary) -> void:
	world.roam.found[String(s["id"])] = true
	if _markers.has(s["id"]):
		(_markers[s["id"]] as Node).queue_free()
		_markers.erase(s["id"])
	Sound.sfx("find")
	var loot: Dictionary = STASH_LOOT[int(String(s["id"]).trim_prefix("stash")) % STASH_LOOT.size()]
	world.notify("Stash: " + String(loot["text"]))
	_reward(loot)
	var c := found_count()
	world.notify("Stashes: %d of %d found." % [c[2], c[3]])
	world._save_game()


func _reward(r: Dictionary) -> void:
	if r.has("money"):
		Life.earn(int(r["money"]), "Found in Lagos (3D)")
		world.notify("+₦%s" % Life.fmt_naira(int(r["money"])))
	if r.has("respect"):
		Story.add_respect(int(r["respect"]))
		world.notify("Respect +%d" % int(r["respect"]))
	if r.has("ammo"):
		if world.combat.armed:
			world.combat.reserve += int(r["ammo"])
			world.notify("+%d rounds" % int(r["ammo"]))
		else:
			Life.earn(3000, "Sold rounds you can't use (3D)")
			world.notify("No gun to use them in. You sell the rounds: +₦3,000")
	if r.has("item"):
		var it := String(r["item"])
		if it == "papers":
			Story.flags["papers"] = true
			world.notify("Got: vehicle papers (checkpoints accept them now)")
		elif it == "jerrycan":
			world.roam.buffs["jerrycan"] = 1e9
			world.notify("Got: a jerrycan of fuel")


# ---------- street encounters ----------

func _encounters(delta: float) -> void:
	if not _enc.is_empty():
		_enc_step(delta)
		return
	_enc_t -= delta
	if _enc_t > 0.0 or world.people_keys.is_empty() or world.combat.active:
		return
	_enc_t = _rng.randf_range(80.0, 160.0)
	var f: Vector3 = world.focus()
	var c: Vector2i = world._walk_cell_near(f, 14.0, 30.0)
	var pos: Vector3 = world.cell_pos(c)
	var kinds := ["pickpocket", "oranges", "fight"]
	if world.ride == null:
		kinds.append("danfo")
	var kind: String = kinds[_rng.randi() % kinds.size()]
	_enc = { "kind": kind, "pos": pos, "nodes": [], "t": 0.0, "prompt": "" }
	match kind:
		"pickpocket":
			_person("market_woman", pos, "argue")
			var thief := _person("agbero", pos + Vector3(2, 0, 1), "run")
			if thief == null:
				_end_encounter(false)
				return
			_enc["thief"] = thief
			_enc["dir"] = (pos - f).normalized() if pos.distance_to(f) > 1.0 else Vector3.RIGHT
			world.notify("\"Thief! Thief! He took my purse!\" Catch him!")
			Sound.sfx("whistle")
		"oranges":
			_person("market_woman", pos, "argue")
			var tray: Node3D = world.models.make("orange_tray")
			if tray:
				Models3D.fit_height(tray, 0.9)
				var h := Node3D.new()
				h.add_child(tray)
				h.position = pos + Vector3(1.0, 0, 0.5)
				h.rotation.z = 1.2
				add_child(h)
				_enc["nodes"].append(h)
			_enc["prompt"] = "HELP HER"
			world.notify("A market woman's tray of oranges has fallen in the road.")
		"fight":
			var a := _person("agbero", pos, "punch")
			var b := _person("agbero", pos + Vector3(1.2, 0, 0), "punch")
			if a and b:
				a.rotation.y = PI * 0.5
				b.rotation.y = -PI * 0.5
			_enc["prompt"] = "BREAK IT UP"
			world.notify("Two boys are fighting on the pavement. People are gathering.")
		"danfo":
			var v: Vehicle3D = world.spawn_owned("danfo", pos)
			if v:
				v.shout("E don knock! Help me push!", 6.0)
				_enc["veh"] = v
			_person("walker", pos + Vector3(1.5, 0, 1.5), "wave")
			_enc["pos"] = v.position if v else pos
			_enc["prompt"] = "PUSH"


func _person(key: String, pos: Vector3, anim: String) -> Person3D:
	if not world.models.has(key, Models3D.CHARS):
		key = String(world.people_keys[0])
	var p := Person3D.new()
	add_child(p)
	if not p.setup(world.models, key, world, Vector2i(int(pos.x / 4.0), int(pos.z / 4.0)), _rng.randi()):
		p.free()
		return null
	p.position = pos
	p.state = Person3D.State.PAUSE
	p.pause_left = 1e9
	Models3D.play(p.ap, anim, "idle")
	(_enc["nodes"] as Array).append(p)
	return p


func _enc_step(delta: float) -> void:
	_enc["t"] = float(_enc["t"]) + delta
	var f: Vector3 = world.focus()
	if (_enc["pos"] as Vector3).distance_to(f) > 120.0 or float(_enc["t"]) > 90.0:
		_end_encounter(false)
		return
	if _enc["kind"] == "pickpocket":
		var thief: Person3D = _enc.get("thief")
		if thief == null or not is_instance_valid(thief):
			_end_encounter(false)
			return
		# He runs away from Dayo, along the pavement where he can.
		var away: Vector3 = thief.position - world.player.position
		away.y = 0.0
		var dir: Vector3 = away.normalized() if away.length() > 0.1 else Vector3.RIGHT
		thief.position += dir * 4.6 * delta
		thief.position.y = world.terrain.height_at(thief.position)
		thief.rotation.y = atan2(dir.x, dir.z)
		Models3D.play(thief.ap, "run", "walk")
		var d: float = away.length()
		if d < 1.5 and world.ride == null:
			Models3D.play(thief.ap, "hit", "idle")
			world.notify("Got him! The woman gets her purse back and presses ₦1,500 on you.")
			Life.earn(1500, "Caught a pickpocket (3D)")
			Story.add_respect(2)
			_end_encounter(true)
		elif d > 45.0 or float(_enc["t"]) > 30.0:
			world.notify("He's gone into the crowd.")
			_end_encounter(false)


func _enc_action() -> void:
	if _enc.is_empty():
		return
	match String(_enc["kind"]):
		"oranges":
			world.player.punch()
			world.notify("You help gather the oranges. \"God bless you, my son!\" She gives you two.")
			world.combat.player_hp = mini(Combat3D.PLAYER_MAX, world.combat.player_hp + 2)
			Story.add_respect(1)
			_end_encounter(true)
		"fight":
			if Story.respect >= 30:
				world.notify("\"Na Sabi! Sorry, sir.\" They stop at once and shake hands.")
				Story.add_respect(1)
				_end_encounter(true)
			else:
				world.notify("\"Who you be? Comot!\" They turn on you.")
				var pos: Vector3 = _enc["pos"]
				_end_encounter(false)
				world.combat.start([{ "id": "e1", "who": "agbero", "type": "thug", "pos": pos }, { "id": "e2", "who": "agbero", "type": "thug", "pos": pos + Vector3(1.2, 0, 0) }])
				var won: bool = await world.combat.finished
				await world.get_tree().create_timer(0.8).timeout
				world.combat.clear()
				if won:
					Story.add_respect(2)
					world.notify("The crowd cheers. (Respect +2)")
		"danfo":
			world.notify("You put your shoulder to it... the engine coughs and catches! \"Thank you, my brother!\"")
			Sound.sfx("success")
			Life.earn(500, "Pushed a stalled danfo (3D)")
			Story.add_respect(1)
			var v: Vehicle3D = _enc.get("veh")
			if v and is_instance_valid(v):
				v.mode = Vehicle3D.Mode.AI
				v.speed = 4.0
				v._nearest_node()
				_enc.erase("veh")
			_end_encounter(true)


func _end_encounter(_ok: bool) -> void:
	if _enc.is_empty():
		return
	for n in _enc.get("nodes", []):
		if is_instance_valid(n):
			var node: Node = n
			var tw := create_tween()
			tw.tween_interval(3.0)
			tw.tween_callback(node.queue_free)
	var v: Variant = _enc.get("veh")
	if v != null and is_instance_valid(v):
		world.vehicles.erase(v)
		(v as Node).queue_free()
	_enc = {}
	if _my_prompt != "" and world.prompt_text == _my_prompt:
		world.prompt_text = ""
		world.prompt_cb = Callable()
		_my_prompt = ""
