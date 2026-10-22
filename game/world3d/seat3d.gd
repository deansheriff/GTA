class_name Seat3D
extends RefCounted
## Characters in vehicles (D-033): Dayo (and okada, keke and horse riders in traffic) sit in the
## vehicle instead of vanishing. The free characters have no sitting clip, so the seat pose is set
## on the skeleton itself: thighs forward, shins down, feet under the knees (these rigs keep the
## feet on separate bones), and the hands reaching forward to the wheel or the handlebars.
## The pose is set once and the character's animation is stopped, so a rider costs no animation.

## Where the driver sits in each kind of vehicle (forward +X, left -Z), the hip height above the
## vehicle's floor, and how far forward the hands reach.
const SEATS := {
	"car": { "at": Vector3(0.1, 0, -0.38), "hip": 0.42, "reach": 0.45 },
	"taxi": { "at": Vector3(0.1, 0, -0.38), "hip": 0.42, "reach": 0.45 },
	"suv": { "at": Vector3(0.2, 0, -0.42), "hip": 0.8, "reach": 0.45 },
	"pickup": { "at": Vector3(0.4, 0, -0.42), "hip": 0.8, "reach": 0.45 },
	"van": { "at": Vector3(1.1, 0, -0.42), "hip": 0.85, "reach": 0.45 },
	"ambulance": { "at": Vector3(1.1, 0, -0.42), "hip": 0.85, "reach": 0.45 },
	"danfo": { "at": Vector3(1.3, 0, -0.5), "hip": 0.9, "reach": 0.45 },
	"bus": { "at": Vector3(4.4, 0, -0.6), "hip": 1.25, "reach": 0.5 },
	"truck": { "at": Vector3(2.9, 0, -0.55), "hip": 1.45, "reach": 0.5 },
	"tanker": { "at": Vector3(3.5, 0, -0.55), "hip": 1.45, "reach": 0.5 },
	"keke": { "at": Vector3(0.45, 0, 0.0), "hip": 0.72, "reach": 0.45 },
	"okada": { "at": Vector3(0.0, 0, 0.0), "hip": 0.8, "reach": 0.55, "straddle": true },
	"horse": { "at": Vector3(0.05, 0, 0.0), "hip": 1.62, "reach": 0.45, "straddle": true },
	"speedboat": { "at": Vector3(-0.6, 0, -0.35), "hip": 0.75, "reach": 0.4 },
	"canoe": { "at": Vector3(-0.9, 0, 0.0), "hip": 0.35, "reach": 0.35 },
}


static func seat_for(kind: String) -> Dictionary:
	return SEATS.get(kind, SEATS["car"])


## A seated character for a vehicle: returns the holder node to add to the vehicle (or null).
static func make_rider(lib: Models3D, key: String, kind: String, tone: int) -> Node3D:
	var got: Array = lib.person(key, 1.75, tone)
	if got[0] == null:
		return null
	var holder := Node3D.new()
	holder.name = "Rider"
	holder.add_child(got[0])
	var s := seat_for(kind)
	holder.position = s["at"]
	holder.rotation.y = PI * 0.5 # the character faces +Z; the vehicle's forward is +X
	holder.set_meta("kind", kind)
	var ap: AnimationPlayer = got[1]
	if ap:
		ap.active = false # the seat pose is set by hand; no clip may overwrite it
	Models3D.no_shadow(holder)
	return holder


## Seat the rider (call once it's in the scene: a skeleton's pose set before that is lost).
static func apply(holder: Node3D) -> void:
	if not is_instance_valid(holder) or holder.get_child_count() == 0:
		return
	var root: Node3D = holder.get_child(0)
	var s := seat_for(String(holder.get_meta("kind", "car")))
	var sks := root.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return
	var sk: Skeleton3D = sks[0]
	sk.reset_bone_poses()
	var chain := _chain(sk, root)
	_sit(sk, chain, bool(s.get("straddle", false)))
	# Hips at the seat's height: lift or sink the whole character to put them there.
	var hb := sk.find_bone("Hips")
	if hb >= 0:
		var hip_local: Vector3 = chain * sk.get_bone_global_pose(hb).origin
		root.position.y = float(s["hip"]) - hip_local.y


## Skeleton space to the person root's space (through the armature's scale and turn).
static func _chain(sk: Skeleton3D, root: Node3D) -> Transform3D:
	var xf := sk.transform
	var n: Node = sk.get_parent()
	while n != null and n != root and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## The seated pose, in skeleton space: works for the 24-clip and 11-clip rigs (UpperLeg/LowerLeg/
## Foot, UpperArm/LowerArm). Parents are set before children, each from the standing pose.
static func _sit(sk: Skeleton3D, chain: Transform3D, straddle: bool) -> void:
	# The character's forward (+Z) and down, as directions in skeleton space.
	var inv := chain.basis.inverse()
	var fwd := (inv * Vector3(0, 0, 1)).normalized()
	var down := (inv * Vector3(0, -1, 0)).normalized()
	var right := (inv * Vector3(1, 0, 0)).normalized()
	var orig := {}
	for b in sk.get_bone_count():
		orig[b] = sk.get_bone_global_pose(b)
	for side in ["L", "R"]:
		var ul := sk.find_bone("UpperLeg." + side)
		var ll := sk.find_bone("LowerLeg." + side)
		var ft := sk.find_bone("Foot." + side)
		if ul < 0 or ll < 0:
			continue
		var hip: Vector3 = (orig[ul] as Transform3D).origin
		var knee: Vector3 = (orig[ll] as Transform3D).origin
		var thigh := hip.distance_to(knee)
		var foot_p: Vector3 = (orig[ft] as Transform3D).origin if ft >= 0 else knee + down * thigh
		var shin := knee.distance_to(foot_p)
		var out := right * (1.0 if side == "L" else -1.0) * (0.3 if straddle else 0.08)
		var knee2 := hip + (fwd + out).normalized() * thigh
		var foot2 := knee2 + (down + (fwd * 0.15 if not straddle else Vector3.ZERO)).normalized() * shin
		_aim(sk, ul, orig[ul], knee - hip, knee2 - hip, hip)
		_aim(sk, ll, orig[ll], foot_p - knee, foot2 - knee2, knee2)
		if ft >= 0:
			var fp: Transform3D = orig[ft]
			fp.origin = foot2
			sk.set_bone_global_pose(ft, fp)
	# Hands forward to the wheel or the bars.
	for side in ["L", "R"]:
		var ua := sk.find_bone("UpperArm." + side)
		var la := sk.find_bone("LowerArm." + side)
		if ua < 0 or la < 0:
			continue
		var wr := sk.find_bone("Wrist." + side)
		if wr < 0:
			wr = sk.find_bone("Palm." + side)
		var sh: Vector3 = (orig[ua] as Transform3D).origin
		var el: Vector3 = (orig[la] as Transform3D).origin
		var wp: Vector3 = (orig[wr] as Transform3D).origin if wr >= 0 else el + down * sh.distance_to(el)
		var x := 1.0 if side == "L" else -1.0
		var el2 := sh + (down * 0.8 + fwd * 0.5 + right * x * 0.12).normalized() * sh.distance_to(el)
		var wp2 := el2 + (fwd + down * 0.1 - right * x * 0.3).normalized() * el.distance_to(wp)
		_aim(sk, ua, orig[ua], el - sh, el2 - sh, sh)
		_aim(sk, la, orig[la], wp - el, wp2 - el2, el2)


## Set a bone's skeleton-space pose: its standing pose turned so `from` points along `to`, with its
## head at `at`.
static func _aim(sk: Skeleton3D, bone: int, standing: Transform3D, from: Vector3, to: Vector3, at: Vector3) -> void:
	if from.length() < 1e-5 or to.length() < 1e-5:
		return
	var g := standing
	g.basis = Basis(Quaternion(from.normalized(), to.normalized())) * g.basis
	g.origin = at
	sk.set_bone_global_pose(bone, g)
