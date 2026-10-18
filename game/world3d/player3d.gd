class_name Player3D
extends CharacterBody3D
## The player on foot in the 3D city (D-020): Tunde, walking or running where the stick points
## (relative to the camera), with idle / walk / run animations. Solid against buildings, props
## and vehicles.

const WALK := 2.0
const RUN := 5.6

var ap: AnimationPlayer
var model: Node3D
var world # Street3D
var moving := 0.0 # 0 idle, 1 walking, 2 running


func setup(lib: Models3D, w) -> void:
	world = w
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.7
	shape.shape = cap
	shape.position.y = 0.85
	add_child(shape)
	var got := lib.person("tunde", 1.75)
	model = got[0]
	ap = got[1]
	if model == null:
		model = _figure()
	add_child(model)
	collision_layer = 4
	collision_mask = 1 | 2
	Models3D.play(ap, "idle", "walk")


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
	if want != moving:
		moving = want
		match int(want):
			0: Models3D.play(ap, "idle", "walk", 1.0)
			1: Models3D.play(ap, "walk", "idle", 1.0)
			2: Models3D.play(ap, "run", "walk", 1.0)


func facing() -> float:
	return model.rotation.y
