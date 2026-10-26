class_name TalkCam3D
extends RefCounted
## The dialogue camera (D-033). While people talk, the camera frames the conversation the way a
## film would, instead of staying on the gameplay view:
##  - someone speaks to Dayo: over Dayo's shoulder onto the speaker's face;
##  - Dayo speaks: the reverse, over the listener's shoulder onto Dayo;
##  - nobody to talk to (narration, a voice): a slow close shot of Dayo;
##  - in a vehicle, or when a mission has set its own camera, it stays out of the way.
## Speakers turn to face whoever they're talking to and play their talk clip. Shots ease in.

var world # Street3D
var active := false
var pos := Vector3.ZERO
var look := Vector3.ZERO
var _listener: Node3D = null # the last person who spoke to Dayo
var _first := true
var _was := "follow" # the camera mode to go back to


func _init(w) -> void:
	world = w


## A dialogue box opened: take the camera (if nothing else has it).
func begin() -> void:
	if world.ride != null or not world.stage.cam_override in ["follow", "look"] or world.in_menu:
		return
	_was = world.stage.cam_override
	active = true
	_first = true
	_first_place = true
	_listener = _nearest_actor(9.0)
	world.stage.cam_override = "talk"


func end() -> void:
	if active and world.stage.cam_override == "talk":
		world.stage.cam_override = _was
	active = false
	_listener = null


## A line was shown: choose the shot for whoever says it.
func line(who: String) -> void:
	if not active:
		return
	var dayo: Node3D = world.player
	if _listener != null and not is_instance_valid(_listener):
		_listener = null # despawned since (a fighter, a guard, an encounter)
	var speaker: Node3D = null
	if who == "dayo" or who == "young_dayo":
		speaker = dayo
	else:
		speaker = _actor_for(who)
		if speaker:
			_listener = speaker
	var other: Node3D = _listener if speaker == dayo else dayo
	if speaker == null:
		# Narration or a voice: a close, slightly low shot of Dayo.
		var f := _facing(dayo)
		_shot(dayo.global_position + f * 2.3 + _side(f) * 0.5 + Vector3(0, 1.45, 0), dayo.global_position + Vector3(0, 1.45, 0))
		return
	var face := _face_pos(speaker)
	if _head(speaker) < 0.6:
		# Lying where they fell: look down at the face from beyond the head, along the body.
		var along := face - speaker.global_position
		along.y = 0.0
		var away := along.normalized() if along.length() > 0.2 else _facing(speaker)
		_shot(face + away * 1.2 + _side(away) * 0.3 + Vector3(0, 1.1, 0), face)
		return
	if other == null or other.global_position.distance_to(speaker.global_position) > 10.0:
		var f := _facing(speaker)
		_shot(speaker.global_position + f * 2.0 + _side(f) * 0.4 + Vector3(0, face.y - speaker.global_position.y + 0.05, 0), face)
		_turn(speaker, speaker.global_position + f)
		return
	# Over the listener's shoulder onto the speaker; both turn to each other.
	_turn(speaker, other.global_position)
	_turn(other, speaker.global_position)
	if speaker is Person3D and (speaker as Person3D).ap and not _posed(speaker):
		Models3D.play((speaker as Person3D).ap, "talk", "idle")
	var d := speaker.global_position - other.global_position
	d.y = 0.0
	var dir := d.normalized()
	var side := _side(dir)
	var cam := other.global_position - dir * 1.25 + side * 0.65 + Vector3(0, 1.7, 0)
	_shot(cam, face)


func _shot(p: Vector3, at: Vector3) -> void:
	# Keep walls out of the shot: pull in towards the subject if something is in the way.
	var q := PhysicsRayQueryParameters3D.create(at, p, 1)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		p = (hit["position"] as Vector3).lerp(at, 0.15)
	pos = p
	look = at
	_cut = true # a new shot is a cut, like film; within a shot the camera only drifts
	if _first:
		_first = false


## The camera follows the shot smoothly (called every frame by Street3D).
func place(cam: Camera3D, delta: float) -> void:
	if _cut or _first_place:
		_cut = false
		_first_place = false
		_drift = 0.0
		cam.position = pos
		_look_cur = look
	else:
		# A slow push in while the line plays.
		_drift = minf(_drift + delta * 0.06, 0.25)
		cam.position = pos.lerp(look, _drift)
		_look_cur = _look_cur.lerp(look, minf(1.0, delta * 5.0))
	if cam.position.distance_to(_look_cur) > 0.2:
		cam.look_at(_look_cur)


var _cut := false
var _drift := 0.0


var _look_cur := Vector3.ZERO
var _first_place := true


func _actor_for(who: String) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for a: Variant in world.stage.actors.values():
		if not is_instance_valid(a):
			continue
		var n: Node3D = a
		if String(n.get_meta("who", "")) != who:
			continue
		var d: float = n.global_position.distance_to(world.player.global_position)
		if d < bd:
			bd = d
			best = n
	return best if bd < 25.0 else null


func _nearest_actor(r: float) -> Node3D:
	var best: Node3D = null
	var bd := r
	for a: Variant in world.stage.actors.values():
		if not is_instance_valid(a):
			continue
		var d: float = (a as Node3D).global_position.distance_to(world.player.global_position)
		if d < bd:
			bd = d
			best = a
	return best


func _facing(n: Node3D) -> Vector3:
	var yaw: float = world.player.facing() if n == world.player else n.rotation.y
	return Vector3(sin(yaw), 0, cos(yaw))


func _side(dir: Vector3) -> Vector3:
	return Vector3(-dir.z, 0, dir.x)


## Where the speaker's face is in the world: the skeleton's Head bone when it has one.
func _face_pos(n: Node3D) -> Vector3:
	var sks := n.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty():
		var sk: Skeleton3D = sks[0]
		var hb := sk.find_bone("Head")
		if hb >= 0:
			return sk.global_transform * sk.get_bone_global_pose(hb).origin
	return n.global_position + Vector3(0, _head(n), 0)


## Roughly how high the speaker's face is: lying dead near the floor, sitting lower, standing at
## eye level.
func _head(n: Node3D) -> float:
	if n is Person3D and (n as Person3D).ap:
		match String((n as Person3D).ap.assigned_animation):
			"dead": return 0.3
			"sit": return 1.0
	return 1.5


## Someone a mission has put in a pose that must hold: lying dead, or sitting.
func _posed(n: Node3D) -> bool:
	if not n is Person3D or (n as Person3D).ap == null:
		return false
	# (assigned_animation: a finished, non-looping death still counts)
	return String((n as Person3D).ap.assigned_animation) in ["dead", "sit"]


func _turn(n: Node3D, at: Vector3) -> void:
	if _posed(n):
		return # the dead don't turn round to talk
	var to := at - n.global_position
	to.y = 0.0
	if to.length() < 0.05:
		return
	if n == world.player:
		world.player.face(at)
	else:
		n.rotation.y = atan2(to.x, to.z)
