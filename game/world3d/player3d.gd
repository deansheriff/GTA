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
func walk(stick: Vector2, cam_yaw: float, run: bool, delta: float) -> void:
	var mag := minf(1.0, stick.length())
	var dir := Vector3.ZERO
	if mag > 0.12:
		# Screen up = away from the camera.
		var fwd := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
		var right := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
		dir = (right * stick.x - fwd * stick.y).normalized()
	var fast := run or mag > 0.92
	var spd := (RUN if fast else WALK) * (1.0 if mag > 0.12 else 0.0)
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd
	velocity.y = 0.0 # flat city: height comes from the terrain (kerbs), not gravity
	move_and_slide()
	position.y = lerpf(position.y, world.terrain.height_at(position), minf(1.0, delta * 14.0))
	if dir != Vector3.ZERO:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(dir.x, dir.z), minf(1.0, delta * 12.0))
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
