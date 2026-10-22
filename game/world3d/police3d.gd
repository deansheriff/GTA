class_name Police3D
extends Node
## Wanted level and police response (P2, D-022; stages D-032). Story.wanted (0-5 stars) rises with
## carjacking, gunfire in the street, hitting people, red lights and blasting checkpoints. The
## response runs in readable stages, shown on the HUD and the minimap:
##   SPOTTED  stars just went up: units are called and head for you;
##   PURSUIT  a unit can see you (70 m and a clear line): they chase, and box you in to arrest;
##   SEARCH   they've lost sight: they drive to where you were last seen and comb the area (a
##            circle on the minimap). Stay out of the circle and out of sight until the search ends
##            and you lose a star; get seen and it's a pursuit again. Swapping vehicles out of sight
##            makes them search the old one;
##   ESCAPED  the stars are gone.
## Boxed in (stopped beside a unit for 2 s) you're BUSTED: a choice to settle (pay) or run for it
## (another star).

enum Stage { CLEAR, SPOTTED, PURSUIT, SEARCH }

const SIGHT := 70.0
const SEARCH_SECS := 18.0

var world # Street3D
var units: Array[Vehicle3D] = []
var stage := Stage.CLEAR
var last_seen := Vector3.ZERO
var search_r := 0.0 # metres: the minimap circle
var search_left := 0.0
var _boxed := 0.0
var _flash_t := 0.0
var _spotted_t := 0.0
var _seen_ride: Vehicle3D = null # what they saw you in
var _bust_open := false
var suspended := false # missions run their own pursuers

signal busted(fine: int)


func setup(w) -> void:
	world = w


func raise(stars: float) -> void:
	var before := Story.wanted
	Story.wanted = clampf(Story.wanted + stars, 0.0, 5.0)
	if Story.wanted > before and not suspended:
		last_seen = world.focus()
		_seen_ride = world.ride
		if stage == Stage.CLEAR or stage == Stage.SEARCH:
			_set_stage(Stage.SPOTTED)
		_spotted_t = 3.0


func label() -> String:
	match stage:
		Stage.SPOTTED: return "SPOTTED · the police are coming"
		Stage.PURSUIT: return "PURSUIT · lose them: break their line of sight"
		Stage.SEARCH: return "SEARCHING · stay out of the circle (%ds)" % int(ceil(search_left))
	return ""


func _set_stage(s: int) -> void:
	if s == stage:
		return
	stage = s
	match s:
		Stage.PURSUIT: Sound.sfx("whistle", 0.9)
		Stage.SEARCH:
			search_left = SEARCH_SECS
			search_r = 60.0 + Story.wanted * 15.0
			world.notify("They've lost sight of you. They're searching the area.")


func step(delta: float) -> void:
	var want := 0 if suspended else int(ceil(Story.wanted - 0.01))
	while units.size() < want:
		_spawn()
	while units.size() > want:
		units.pop_back().queue_free()
	if want == 0:
		if stage != Stage.CLEAR:
			if not suspended:
				world.notify("ESCAPED. The police have given up.")
			_set_stage(Stage.CLEAR)
		_boxed = 0.0
		return
	_flash_t += delta
	var f: Vector3 = world.focus()
	var seen := false
	var close := false
	for u in units:
		if stage == Stage.SEARCH or stage == Stage.SPOTTED and _spotted_t > 0.0:
			_search_drive(u, delta)
		else:
			u.chase_step(delta)
		var d := u.position.distance_to(f)
		if d < SIGHT and _can_see(u, f):
			# Swapped rides out of their sight: they're still looking for the old one.
			if stage == Stage.SEARCH and _seen_ride != null and world.ride != _seen_ride and d > 25.0:
				continue
			seen = true
		if d < 7.0:
			close = true
		_flash(u)
	_spotted_t = maxf(0.0, _spotted_t - delta)
	if seen:
		last_seen = f
		_seen_ride = world.ride
		if stage != Stage.PURSUIT:
			_set_stage(Stage.PURSUIT)
	elif stage == Stage.PURSUIT:
		_set_stage(Stage.SEARCH)
	elif stage == Stage.SPOTTED and _spotted_t <= 0.0:
		_set_stage(Stage.SEARCH)
	if stage == Stage.SEARCH:
		# Lingering inside the search circle keeps them searching longer.
		var inside := Vector2(f.x - last_seen.x, f.z - last_seen.z).length() < search_r
		search_left -= delta * (0.35 if inside else 1.0) * (world.roam.wanted_k() if world.roam else 1.0)
		search_r = maxf(30.0, search_r - delta * 1.5)
		if search_left <= 0.0:
			Story.wanted = maxf(0.0, Story.wanted - 1.0)
			if Story.wanted > 0.0:
				world.notify("Search called off. Wanted level down.")
				search_left = SEARCH_SECS
	var stopped: bool = world.ride == null or absf(world.ride.speed) < 2.0
	_boxed = _boxed + delta if close and stopped and stage == Stage.PURSUIT else 0.0
	if _boxed > 2.0 and not _bust_open:
		_boxed = 0.0
		_bust()


func _can_see(u: Vehicle3D, f: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(u.position + Vector3(0, 1.6, 0), f + Vector3(0, 1.2, 0), 1)
	return world.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Searching: head for where you were last seen, then circle round it.
func _search_drive(u: Vehicle3D, delta: float) -> void:
	var t := float(u.get_instance_id() % 628) / 100.0 + _flash_t * 0.15
	var goal := last_seen + Vector3(cos(t), 0, sin(t)) * search_r * 0.5
	var to := goal - u.position
	to.y = 0.0
	if to.length() > 4.0:
		u.heading = lerp_angle(u.heading, -Vector2(to.x, to.z).angle(), minf(1.0, delta * 2.0))
		u.speed = move_toward(u.speed, float(u.spec["top"]) * 0.5, float(u.spec["accel"]) * delta)
	else:
		u.speed = move_toward(u.speed, 0.0, 6.0 * delta)
	u._move(delta)


## Boxed in: settle, or run for it.
func _bust() -> void:
	_bust_open = true
	var fine := maxi(2000, int(Life.money * 0.1))
	if world.roam and world.roam.perk("chairman"):
		fine /= 2
	var picked: Array = await world.say([{ "who": "police", "text": "Oya come down! You think say you fit run from us? Na ₦%s bail." % Life.fmt_naira(fine), "choices": [
		{ "id": "settle", "text": "Settle it (₦%s). The stars clear." % Life.fmt_naira(fine) },
		{ "id": "run", "text": "Run for it. (Another star.)" },
	] }])
	_bust_open = false
	var c := String((picked[0] as Dictionary).get("id", "settle")) if not picked.is_empty() else "settle"
	if c == "settle":
		Life.spend(mini(fine, int(Life.money)), "Busted by the police (3D)")
		Story.wanted = 0.0
		busted.emit(fine)
		world.notify("BUSTED. They took ₦%s \"for bail\" and let you go." % Life.fmt_naira(fine))
	else:
		Story.wanted = minf(5.0, Story.wanted + 1.0)
		_spotted_t = 1.0
		world.notify("You ran! They're right behind you.")


func _spawn() -> void:
	var v := Vehicle3D.new()
	world.add_child(v)
	v.setup(world.models, "pickup", world)
	v.mode = Vehicle3D.Mode.CHASE
	# Arrive from a road node out of sight.
	var f: Vector3 = world.focus()
	var keys: Array = world.map.road_nodes.keys()
	var best: String = keys[0]
	for id: String in keys:
		var d := Terrain3D.w(world.map.road_nodes[id]).distance_to(f)
		if d > 110.0 and d < 200.0:
			best = id
			break
	v.position = Terrain3D.w(world.map.road_nodes[best])
	v.b = best
	v.a = best
	var light := OmniLight3D.new()
	light.name = "Siren"
	light.omni_range = 9.0
	light.light_energy = 2.0
	light.position = Vector3(0, 2.3, 0)
	v.add_child(light)
	var bar := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.12, 1.2)
	bar.mesh = bm
	bar.name = "Bar"
	bar.position = Vector3(-0.2, 2.05, 0)
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.1, 0.1)
	mat.emission_energy_multiplier = 3.0
	bar.material_override = mat
	v.add_child(bar)
	# The siren wails from the car itself: you hear it coming, and from which side.
	var siren := AudioStreamPlayer3D.new()
	siren.stream = Sound.loop_stream("res://audio/sfx/siren.wav")
	siren.bus = "SFX"
	siren.unit_size = 12.0
	siren.max_distance = 180.0
	siren.volume_db = -6.0
	siren.autoplay = true
	v.add_child(siren)
	units.append(v)


func _flash(u: Vehicle3D) -> void:
	var red := int(_flash_t * 4.0) % 2 == 0
	var l := u.get_node_or_null("Siren") as OmniLight3D
	if l:
		l.light_color = Color(0.9, 0.1, 0.1) if red else Color(0.15, 0.3, 1.0)
	var bar := u.get_node_or_null("Bar") as MeshInstance3D
	if bar:
		(bar.material_override as StandardMaterial3D).emission = Color(0.9, 0.1, 0.1) if red else Color(0.15, 0.3, 1.0)


func clear() -> void:
	for u in units:
		u.queue_free()
	units.clear()
	stage = Stage.CLEAR
