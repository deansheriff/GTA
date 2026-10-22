class_name Player3D
extends CharacterBody3D
## The player on foot (D-020, D-021): Dayo (or young Dayo in the prologue), walking or running where
## the stick points (relative to the camera), punching and flinching in fights. Solid against
## buildings, props and vehicles.

const WALK := 2.0
const RUN := 5.6

var ap: AnimationPlayer
var model: Node3D
var world # Street3D
var moving := 0.0 # 0 idle, 1 walking, 2 running
var model_key := ""
var _lib: Models3D
var _action_t := 0.0 # a one-off clip (punch, hit) is playing
var _gun: Node3D
var armed := false # holding the pistol: gun stance when standing
var _hand := -1
var _elbow := -1
var _gun_x := true # the pistol's barrel runs along its X axis (else Z)
var _skel: Skeleton3D
## Stamina (D-028): sprinting uses it up; Mama Àgbà's amala and ewedu make it last.
var stamina := 1.0
var stamina_k := 1.0 # drain multiplier (food buffs lower it)
var _winded := false
var in_cover := false # standing still against a wall: gunmen hit far less often
var _vault := {} # mid-jump across a rooftop gap: {from, to, t, dur}
var _cover_t := 0.0


func setup(lib: Models3D, w) -> void:
	world = w
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.7
	shape.shape = cap
	shape.position.y = 0.85
	add_child(shape)
	_lib = lib
	Blob3D.add(self, Vector2(1.0, 1.0))
	set_model("dayo")
	collision_layer = 4
	collision_mask = 1 | 2


## Swap who we play as (young Dayo in the prologue). Falls back to other rigged people.
func set_model(key: String) -> void:
	if key == model_key and model != null:
		return
	var face := model.rotation.y if model else 0.0
	if model:
		model.queue_free()
	model_key = key
	var got: Array = [null, null]
	for k in [key, "dayo", "tunde", "walker"]:
		got = _lib.person(k, 1.75)
		if got[0] != null:
			break
	model = got[0] if got[0] != null else _figure()
	ap = got[1]
	model.rotation.y = face
	add_child(model)
	moving = -1.0
	Models3D.play(ap, "idle", "walk")


## The pistol in Dayo's right hand (free CC0 model, D-024). It follows the hand bone each frame
## (Meshy skeletons are in centimetres under a 0.01-scaled Armature, so a plain child would be
## scaled down with it).
func show_gun(on: bool) -> void:
	if on and _gun == null:
		var g: Node3D = _lib.make("pistol", "res://art3d/free/")
		if g == null:
			return
		var bb := Models3D.aabb(g)
		_gun_x = bb.size.x >= bb.size.z
		var k := 0.2 / maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
		g.scale = Vector3.ONE * k
		g.position = -bb.get_center() * k
		_gun = Node3D.new()
		_gun.add_child(g)
		add_child(_gun)
	if _gun:
		_gun.visible = on and visible
	if on != armed:
		armed = on
		moving = -1.0 # re-pick the standing clip


func _process(_d: float) -> void:
	if _gun == null or not _gun.visible:
		return
	if _skel == null or not is_instance_valid(_skel):
		var sks := model.find_children("*", "Skeleton3D", true, false)
		if sks.is_empty():
			return
		_skel = sks[0]
		_hand = _skel.find_bone("RightHand")
		_elbow = _skel.find_bone("RightForeArm")
		if _hand < 0:
			_hand = _skel.find_bone("Wrist.R") # Quaternius rigs
			_elbow = _skel.find_bone("LowerArm.R")
	if _hand < 0:
		return
	# Aim along the forearm (elbow -> wrist) with the grip down: works for any rig and its scale.
	var wrist := (_skel.global_transform * _skel.get_bone_global_pose(_hand)).origin
	var fwd := model.global_transform.basis.z
	if _elbow >= 0:
		fwd = (wrist - (_skel.global_transform * _skel.get_bone_global_pose(_elbow)).origin).normalized()
	var up := (Vector3.UP - fwd * fwd.dot(Vector3.UP)).normalized()
	if up.length() < 0.1:
		up = model.global_transform.basis.z
	var b := Basis(fwd, up, fwd.cross(up)) if _gun_x else Basis(up.cross(fwd), up, fwd)
	_gun.global_transform = Transform3D(b, wrist + fwd * 0.06)


func shoot_anim() -> void:
	_action_t = 0.3
	Models3D.play(ap, "shoot", "punch", 1.4)


func punch() -> void:
	_action_t = 0.4
	Models3D.play(ap, "punch", "idle", 1.6)


func flinch() -> void:
	_action_t = 0.35
	Models3D.play(ap, "hit", "idle", 1.4)


func face(pos: Vector3) -> void:
	var to := pos - position
	model.rotation.y = atan2(to.x, to.z)


func _figure() -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.3
	cm.height = 1.75
	mi.mesh = cm
	mi.position.y = 0.88
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#a8382c")
	mi.material_override = m
	root.add_child(mi)
	return root


## stick: x right, y down (screen); cam_yaw: the camera's yaw. run: sprint held.
## Walks on the terrain, decks and set floors (World.ground_at); never into open water. Running
## at a short gap between rooftops jumps it (auto-vault); walking stops at the edge.
func walk(stick: Vector2, cam_yaw: float, run: bool, delta: float) -> void:
	if not _vault.is_empty():
		_vault_step(delta)
		return
	var mag := minf(1.0, stick.length())
	var dir := Vector3.ZERO
	if mag > 0.12:
		# Screen up = away from the camera.
		var fwd := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
		var right := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
		dir = (right * stick.x - fwd * stick.y).normalized()
	var fast := (run or mag > 0.92) and not _winded
	var spd := (RUN if fast else WALK) * (1.0 if mag > 0.12 else 0.0)
	if fast and spd > 0.0:
		stamina = maxf(0.0, stamina - delta * 0.055 * stamina_k)
		if stamina <= 0.0:
			_winded = true
	else:
		stamina = minf(1.0, stamina + delta * 0.12)
		if _winded and stamina > 0.35:
			_winded = false
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd
	velocity.y = 0.0 # flat city: height comes from the terrain, decks and kerbs, not gravity
	if spd > 0.0:
		var nxt := position + velocity * delta + dir * 0.35
		var g: float = world.ground_at(nxt, position.y)
		if is_nan(g) or g < position.y - 1.6:
			if fast and _try_vault(dir):
				return
			velocity.x = 0.0
			velocity.z = 0.0
	move_and_slide()
	var here: float = world.ground_at(position, position.y)
	if not is_nan(here):
		position.y = lerpf(position.y, here, minf(1.0, delta * (14.0 if here > position.y else 9.0)))
	if dir != Vector3.ZERO:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(dir.x, dir.z), minf(1.0, delta * 12.0))
	_cover_check(spd == 0.0, delta)
	var want := 0.0 if spd == 0.0 else (2.0 if fast else 1.0)
	if _action_t > 0.0:
		_action_t -= delta
		if _action_t <= 0.0:
			moving = -1.0
		return
	if want != moving:
		moving = want
		match int(want):
			0: Models3D.play(ap, "gun_idle" if armed else "idle", "idle", 1.0)
			1: Models3D.play(ap, "walk", "idle", 1.0)
			2: Models3D.play(ap, "run", "walk", 1.0)


func facing() -> float:
	return model.rotation.y


## A gap ahead (a rooftop edge, a canoe's gap): look up to 4.5 m on for somewhere to land.
func _try_vault(dir: Vector3) -> bool:
	for i in range(2, 10):
		var d := i * 0.5
		var p := position + dir * d
		var g: float = world.ground_at(p, position.y + 0.4)
		if not is_nan(g) and g > position.y - 2.5:
			var land := p + dir * 0.4
			land.y = g
			_vault = { "from": position, "to": land, "t": 0.0, "dur": 0.32 + d * 0.06 }
			Models3D.play(ap, "jump", "run", 1.3)
			Sound.sfx("whoosh", 1.2)
			return true
	return false


func _vault_step(delta: float) -> void:
	_vault["t"] = float(_vault["t"]) + delta
	var k := clampf(float(_vault["t"]) / float(_vault["dur"]), 0.0, 1.0)
	var a: Vector3 = _vault["from"]
	var b: Vector3 = _vault["to"]
	position = a.lerp(b, k) + Vector3(0, sin(k * PI) * 0.9, 0)
	if k >= 1.0:
		_vault = {}
		moving = -1.0


func vaulting() -> bool:
	return not _vault.is_empty()


## In cover: stood still for a moment with a wall within arm's reach.
func _cover_check(still: bool, delta: float) -> void:
	_cover_t = _cover_t + delta if still else 0.0
	if _cover_t < 0.4:
		in_cover = false
		return
	if int(_cover_t * 10.0) % 3 != 0:
		return
	var space := get_world_3d().direct_space_state
	var c := position + Vector3(0, 0.9, 0)
	in_cover = false
	for k in 8:
		var d := Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0))
		var q := PhysicsRayQueryParameters3D.create(c, c + d * 1.3, 1 | 2)
		q.exclude = [get_rid()]
		if not space.intersect_ray(q).is_empty():
			in_cover = true
			return
