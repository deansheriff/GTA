class_name StreetDetail3D
extends RefCounted
## Deliberate street detail (D-032), placed thickest round the landmarks and markets and thinner
## everywhere else, all batched into City3D's chunked MultiMeshes:
##  - patched road: darker squares of newer asphalt over old potholes;
##  - open gutters: a concrete lip and dark water along the kerb;
##  - hanging cables: sagging wires from pole to pole;
##  - litter: pure-water sachets, nylon bags, cans and paper on the pavements;
##  - puddles in the dips, which only show (and shine) when the road is wet.

const K := Terrain3D.K


## level: 0 Low (patches only), 1 Medium (+ gutters and cables), 2 High (+ litter and puddles).
static func build(city: City3D, level := 2) -> void:
	var map: MapData = city.map
	var rng := RandomNumberGenerator.new()
	rng.seed = 3232
	var hot: Array[Vector2] = [] # landmark positions (metres): detail is densest round them
	for id in map.landmarks:
		hot.append((map.landmarks[id]["pos"] as Vector2) * K)
	var near_hot := func(p: Vector2) -> float:
		var best := INF
		for q in hot:
			best = minf(best, p.distance_squared_to(q))
		return sqrt(best)
	# Patches, puddles and gutters along every road.
	for r: Dictionary in map.roads:
		var pts: PackedVector2Array = r["points"]
		var half: float = float(r["width"]) * K * 0.5
		for i in pts.size() - 1:
			var a := pts[i] * K
			var b := pts[i + 1] * K
			var seg := a.distance_to(b)
			var dir := (b - a) / maxf(seg, 0.001)
			var side := Vector2(-dir.y, dir.x)
			var yaw := -dir.angle()
			var t := 6.0
			while t < seg - 6.0:
				var p := a + dir * t
				var dh: float = near_hot.call(p)
				var dense := dh < 130.0
				var surf := map.surface_at(p / K)
				if surf == MapData.S.ROAD:
					if rng.randf() < (0.22 if dense else 0.05):
						var off := side * rng.randf_range(-half * 0.7, half * 0.7)
						var sz := Vector3(rng.randf_range(1.4, 4.0), 1.0, rng.randf_range(1.0, 2.4))
						city._queue("patch", Transform3D(Basis(Vector3.UP, yaw + rng.randf_range(-0.15, 0.15)) * Basis.from_scale(sz), Vector3(p.x + off.x, Terrain3D.ROAD_Y + 0.012, p.y + off.y)), 90.0, false)
					if level >= 2 and rng.randf() < (0.25 if dense else 0.08):
						var off2 := side * (half - rng.randf_range(0.4, 1.2)) * (1.0 if rng.randf() < 0.5 else -1.0)
						var s2 := rng.randf_range(0.8, 2.2)
						city._queue("puddle", Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(s2, 1.0, s2 * rng.randf_range(0.5, 0.9))), Vector3(p.x + off2.x, Terrain3D.ROAD_Y + 0.016, p.y + off2.y)), 80.0, false)
				# Open gutters along the kerbs of the busy streets.
				if level >= 1 and dense and surf == MapData.S.ROAD:
					for s: float in [-1.0, 1.0]:
						var g := p + side * s * (half + MapData.GUTTER_W * K * 0.5)
						if map.surface_at(g / K) != MapData.S.GUTTER and map.surface_at(g / K) != MapData.S.WALK:
							continue
						city._queue("gutter_water", Transform3D(Basis(Vector3.UP, yaw), Vector3(g.x, 0.012, g.y)), 70.0, false)
						var lip := p + side * s * (half + MapData.GUTTER_W * K)
						city._queue("gutter_lip", Transform3D(Basis(Vector3.UP, yaw), Vector3(lip.x, 0.07, lip.y)), 70.0, false)
				t += 2.0 if dense else 9.0
	if level >= 1:
		_cables(city, map)
	if level < 2:
		return
	# Litter on the pavements, thick near the markets and parks.
	var litter := ["litter_sachet", "litter_bag", "litter_can", "litter_paper"]
	for y in map.rows:
		for x in map.cols:
			var s := map.surface[y * map.cols + x]
			if s != MapData.S.WALK and s != MapData.S.GUTTER:
				continue
			var c := Vector2((x + 0.5) * Terrain3D.CELL_M, (y + 0.5) * Terrain3D.CELL_M)
			var dh: float = near_hot.call(c)
			var n := 3 if dh < 40.0 else (1 if dh < 120.0 or rng.randf() < 0.25 else 0)
			for k in n:
				var q := c + Vector2(rng.randf_range(-1.8, 1.8), rng.randf_range(-1.8, 1.8))
				var key: String = litter[rng.randi() % litter.size()]
				city._queue(key, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(q.x, Terrain3D.WALK_H + 0.01, q.y)), 40.0, false)
static func _cables(city: City3D, map: MapData) -> void:
	# Cables: from each street pole to its neighbours along the road, sagging between them.
	var poles: Array[Vector2] = []
	for pr in map.props:
		if pr.kind == "pole":
			poles.append(pr.pos * K)
	var linked := {}
	for i in poles.size():
		var best := -1
		var bd := INF
		for j in poles.size():
			if j == i or linked.has(Vector2i(mini(i, j), maxi(i, j))):
				continue
			var d := poles[i].distance_to(poles[j])
			if d > 10.0 and d < 45.0 and d < bd:
				bd = d
				best = j
		if best < 0:
			continue
		linked[Vector2i(mini(i, best), maxi(i, best))] = true
		for wire in 2:
			_wire(city, poles[i], poles[best], 7.3 - wire * 0.45, 0.6 + wire * 0.25)


## A sagging wire from a to b (metres, on the ground plane) at height h, dipping `sag` in the middle.
static func _wire(city: City3D, a: Vector2, b: Vector2, h: float, sag: float) -> void:
	var n := 6
	var prev := Vector3(a.x, h, a.y)
	for k in range(1, n + 1):
		var t := float(k) / n
		var p2 := a.lerp(b, t)
		var cur := Vector3(p2.x, h - sag * 4.0 * t * (1.0 - t), p2.y)
		var mid := (prev + cur) * 0.5
		var d := cur - prev
		var len := d.length()
		var basis := Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.RIGHT)
		city._queue("cable", Transform3D(basis * Basis.from_scale(Vector3(1, 1, len)), mid), 90.0, false)
		prev = cur
