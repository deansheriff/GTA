class_name Stealth3D
extends Node3D
## Stealth (D-028), for the ballot-box swap, the Iri Ji infiltration and the Blackout:
##  - guards walk their beats with torches; each sees a cone in front of him (a pale fan on the
##    ground shows it);
##  - darkness hides Dayo: at night a guard sees about 9 m, in light (a generator's pool, a torch
##    beam, daylight) 16 m; walking is quieter than running;
##  - being seen fills the guard's alarm ("?" then "!"); a full alarm means spotted;
##  - from behind, PUNCH is a silent takedown;
##  - light pools: generators coughing on and off in the houses round about (the Blackout).
## Mission3D's "stealth" step builds a scene of guards and pools, and waits for Dayo to reach the
## goal (or be spotted).

signal spotted

var world # Street3D
var active := false
var guards: Array = [] # {node: Person3D, path: [Vector3], i, alarm, down, cone: MeshInstance3D, mark: Label3D, torch}
var pools: Array = [] # {pos, radius, on, t, light}
var alarm := 0.0 # the highest guard alarm 0..1 (HUD meter)
var _cone_mat: StandardMaterial3D
var _cone_hot: StandardMaterial3D
var _rng := RandomNumberGenerator.new()

const NIGHT_SIGHT := 9.0
const LIT_SIGHT := 16.0
const HALF_ANGLE := 0.72 # radians either side of a guard's nose


func setup(w) -> void:
	world = w
	_cone_mat = StandardMaterial3D.new()
	_cone_mat.albedo_color = Color(1.0, 0.95, 0.7, 0.16)
	_cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cone_hot = _cone_mat.duplicate()
	_cone_hot.albedo_color = Color(1.0, 0.25, 0.15, 0.28)


## guards: [{who, path: [Vector3...]}], pools: [{pos, radius}]
func begin(guard_specs: Array, pool_specs: Array) -> void:
	end()
	active = true
	alarm = 0.0
	for i in guard_specs.size():
		var g: Dictionary = guard_specs[i]
		var path: Array = g["path"]
		var n: Person3D = world.spawn_actor("guard%d" % i, String(g.get("who", "police")), path[0], "walk")
		if n == null:
			continue
		var cone := MeshInstance3D.new()
		cone.mesh = _fan(NIGHT_SIGHT)
		cone.material_override = _cone_mat
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cone.position.y = 0.06
		n.add_child(cone)
		var torch := SpotLight3D.new()
		torch.light_color = Color("#fff4d0")
		torch.light_energy = 2.2
		torch.spot_range = 14.0
		torch.spot_angle = 24.0
		torch.position = Vector3(0.25, 1.3, 0.2)
		torch.rotation.x = -0.25
		torch.rotation.y = PI # SpotLight shines down -Z; the model faces +Z
		n.add_child(torch)
		var mark := Label3D.new()
		mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		mark.no_depth_test = true
		mark.font_size = 96
		mark.pixel_size = 0.01
		mark.outline_size = 12
		mark.position = Vector3(0, 2.3, 0)
		mark.text = ""
		n.add_child(mark)
		guards.append({ "id": "guard%d" % i, "node": n, "path": path, "i": 1 % path.size(), "alarm": 0.0, "down": false, "cone": cone, "mark": mark, "wait": 0.0 })
	for p: Dictionary in pool_specs:
		var l := OmniLight3D.new()
		l.light_color = Color("#ffd9a0")
		l.omni_range = float(p.get("radius", 7.0)) * 1.4
		l.light_energy = 0.0
		add_child(l)
		l.global_position = (p["pos"] as Vector3) + Vector3(0, 3.0, 0)
		pools.append({ "pos": p["pos"], "radius": float(p.get("radius", 7.0)), "on": false, "t": _rng.randf_range(1.0, 5.0), "light": l })


func end() -> void:
	for g: Dictionary in guards:
		if is_instance_valid(g["node"]):
			world.despawn_actor(String(g["id"]))
	guards.clear()
	for p: Dictionary in pools:
		if is_instance_valid(p["light"]):
			(p["light"] as Node).queue_free()
	pools.clear()
	active = false
	alarm = 0.0


func step(delta: float) -> void:
	if not active:
		return
	# Generators cough on and off: pools of light come and go.
	for p: Dictionary in pools:
		p["t"] = float(p["t"]) - delta
		if float(p["t"]) <= 0.0:
			p["on"] = not bool(p["on"])
			p["t"] = _rng.randf_range(4.0, 9.0) if p["on"] else _rng.randf_range(2.0, 6.0)
			if p["on"]:
				Sound.sfx("power_on", 0.9)
		(p["light"] as OmniLight3D).light_energy = lerpf((p["light"] as OmniLight3D).light_energy, 2.0 if p["on"] else 0.0, minf(1.0, delta * 6.0))
	var pp: Vector3 = world.player.position
	var night: bool = world._dark > 0.5
	var lit := not night
	for p: Dictionary in pools:
		if p["on"] and Vector2(pp.x - p["pos"].x, pp.z - p["pos"].z).length() < float(p["radius"]):
			lit = true
	var running: bool = world.player.moving >= 2.0
	alarm = 0.0
	for g: Dictionary in guards:
		var n: Person3D = g["node"]
		if not is_instance_valid(n) or g["down"]:
			continue
		_patrol(g, n, delta)
		var sight := LIT_SIGHT if lit else NIGHT_SIGHT
		if running:
			sight *= 1.25
		var to := pp - n.position
		to.y = 0.0
		var d := to.length()
		var fwd := Vector3(sin(n.rotation.y), 0, cos(n.rotation.y))
		var seen := d < sight and to.normalized().dot(fwd) > cos(HALF_ANGLE) and _clear_line(n.position, pp)
		# Too close: he hears you even behind him, if you run.
		if d < 2.5 and running:
			seen = true
		var rate := (1.6 if lit else 0.9) * (1.6 if running else 1.0) * clampf(1.4 - d / sight, 0.3, 1.4)
		g["alarm"] = clampf(float(g["alarm"]) + (delta * rate if seen else -delta * 0.35), 0.0, 1.0)
		if seen:
			n.rotation.y = lerp_angle(n.rotation.y, atan2(to.x, to.z), minf(1.0, delta * 2.0))
		var a := float(g["alarm"])
		(g["mark"] as Label3D).text = "!" if a > 0.7 else ("?" if a > 0.05 else "")
		(g["mark"] as Label3D).modulate = Color("#e8483a") if a > 0.7 else Color("#f6d04d")
		(g["cone"] as MeshInstance3D).material_override = _cone_hot if a > 0.05 else _cone_mat
		alarm = maxf(alarm, a)
		if a >= 1.0:
			spotted.emit()


func _patrol(g: Dictionary, n: Person3D, delta: float) -> void:
	if float(g["alarm"]) > 0.3:
		Models3D.play(n.ap, "idle", "")
		return
	if float(g["wait"]) > 0.0:
		g["wait"] = float(g["wait"]) - delta
		Models3D.play(n.ap, "idle", "")
		return
	var path: Array = g["path"]
	if path.size() < 2:
		return
	var tgt: Vector3 = path[int(g["i"])]
	var to := tgt - n.position
	to.y = 0.0
	if to.length() < 0.4:
		g["i"] = (int(g["i"]) + 1) % path.size()
		g["wait"] = _rng.randf_range(1.0, 2.5) # stops to sweep the torch
		return
	n.position += to.normalized() * 1.25 * delta
	n.rotation.y = lerp_angle(n.rotation.y, atan2(to.x, to.z), minf(1.0, delta * 4.0))
	Models3D.play(n.ap, "walk", "idle")


func _clear_line(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a + Vector3(0, 1.5, 0), b + Vector3(0, 1.2, 0), 1)
	return world.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## A guard close in front of Dayo with his back to him goes down without a sound.
func try_takedown() -> bool:
	var pp: Vector3 = world.player.position
	for g: Dictionary in guards:
		var n: Person3D = g["node"]
		if g["down"] or not is_instance_valid(n):
			continue
		var to := pp - n.position
		to.y = 0.0
		if to.length() > 1.8:
			continue
		var fwd := Vector3(sin(n.rotation.y), 0, cos(n.rotation.y))
		if to.normalized().dot(fwd) > -0.2 and float(g["alarm"]) < 0.7:
			continue # he can see you coming
		g["down"] = true
		g["alarm"] = 0.0
		(g["mark"] as Label3D).text = ""
		(g["cone"] as Node3D).visible = false
		for c in n.get_children():
			if c is SpotLight3D:
				(c as SpotLight3D).visible = false
		world.player.face(n.position)
		world.player.punch()
		Models3D.play(n.ap, "dead", "hit")
		Sound.sfx("punch", 0.7)
		world.notify("Takedown. Silent.")
		return true
	return false


func guards_down() -> int:
	return guards.filter(func(g: Dictionary) -> bool: return g["down"]).size()


## The fan a guard sees: a flat sector on the ground.
func _fan(r: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 10
	for i in n:
		var a0 := -HALF_ANGLE + 2.0 * HALF_ANGLE * i / n
		var a1 := -HALF_ANGLE + 2.0 * HALF_ANGLE * (i + 1) / n
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(sin(a1), 0, cos(a1)) * r)
		st.add_vertex(Vector3(sin(a0), 0, cos(a0)) * r)
	return st.commit()
