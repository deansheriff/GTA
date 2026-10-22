class_name Ambience3D
extends Node3D
## Sound you hear where it comes from (D-033): market chatter round the markets and motor parks,
## waves where the lagoon meets the land, a generator thudding in a yard, and each region's own
## background (birds in Abeokuta and Anambra, insects and frogs in the creeks). A handful of
## emitters follow the player about, so it costs the same anywhere.

var world # Street3D
var _market: Array[AudioStreamPlayer3D] = []
var _waves: AudioStreamPlayer3D
var _gen: AudioStreamPlayer3D
var _t := 0.0
var _markets: Array[Vector3] = []
var _gens: Array[Vector3] = []


func setup(w) -> void:
	world = w
	for i in 2:
		_market.append(_emitter("market", 14.0, 95.0, -4.0))
	_waves = _emitter("waves", 10.0, 70.0, -6.0)
	_gen = _emitter("generator", 4.0, 40.0, -8.0)
	on_region()


func _emitter(name: String, unit: float, far: float, db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = "Ambience"
	p.stream = Sound.loop_stream("res://audio/amb/%s.wav" % name)
	p.unit_size = unit
	p.max_distance = far
	p.volume_db = db
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(p)
	return p


## A new map: find its markets, parks and generators, and set the region's background.
func on_region() -> void:
	var map: MapData = world.map
	_markets.clear()
	for id in map.landmarks:
		var lm: Dictionary = map.landmarks[id]
		if String(lm["kind"]) in ["market", "park"]:
			_markets.append(Terrain3D.w(lm["pos"]))
	_gens.clear()
	for pr in map.props:
		if pr.kind == "generator":
			_gens.append(Terrain3D.w(pr.pos))
	Sound.bed({ "abeokuta": "birds", "anambra": "birds", "delta": "insects" }.get(world.region, ""))


func step(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 1.0
	var f: Vector3 = world.focus()
	var night: bool = world._dark > 0.5
	# The two nearest markets or parks.
	var near := _markets.filter(func(p: Vector3) -> bool: return p.distance_to(f) < 110.0)
	near.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_to(f) < b.distance_to(f))
	for i in _market.size():
		var e := _market[i]
		if i < near.size():
			e.global_position = near[i] + Vector3(0, 2, 0)
			e.volume_db = -14.0 if night else -4.0
			if not e.playing:
				e.play()
		elif e.playing:
			e.stop()
	# Waves at the nearest shore.
	var shore: Variant = _nearest_water(f, 50.0)
	if shore != null:
		_waves.global_position = shore
		if not _waves.playing:
			_waves.play()
	elif _waves.playing:
		_waves.stop()
	# The nearest generator (louder when NEPA has taken light).
	var best := Vector3.INF
	for g in _gens:
		if g.distance_to(f) < best.distance_to(f):
			best = g
	if best != Vector3.INF and best.distance_to(f) < 40.0:
		_gen.global_position = best + Vector3(0, 0.5, 0)
		_gen.volume_db = -4.0 if world.roam and not world.roam.nepa_on() else -12.0
		if not _gen.playing:
			_gen.play()
	elif _gen.playing:
		_gen.stop()


func _nearest_water(f: Vector3, r: float) -> Variant:
	if world.is_water_at(f):
		return f
	for ring in range(1, int(r / 4.0) + 1):
		for k in 12:
			var q := f + Vector3(cos(k * TAU / 12.0), 0, sin(k * TAU / 12.0)) * ring * 4.0
			if world.is_water_at(q):
				return q
	return null
