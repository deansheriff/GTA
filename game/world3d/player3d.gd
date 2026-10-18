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
			0: Models3D.play(ap, "idle", "walk", 1.0)
			1: Models3D.play(ap, "walk", "idle", 1.0)
			2: Models3D.play(ap, "run", "walk", 1.0)


func facing() -> float:
	return model.rotation.y
