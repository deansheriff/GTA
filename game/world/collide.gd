class_name Collide
extends RefCounted
## Oriented-box collision for vehicles (separating-axis test). Vehicles are rectangles centred on
## their node: LENGTH along the heading, WIDTH across it.


## Minimum translation vector that pushes box A out of box B (Vector2.ZERO when they don't touch).
static func obb_mtv(a_pos: Vector2, a_rot: float, a_half: Vector2, b_pos: Vector2, b_rot: float, b_half: Vector2) -> Vector2:
	var d := a_pos - b_pos
	# Cheap reject: bounding circles.
	if d.length() > a_half.length() + b_half.length():
		return Vector2.ZERO
	var axes := [Vector2.from_angle(a_rot), Vector2.from_angle(a_rot + PI / 2.0), Vector2.from_angle(b_rot), Vector2.from_angle(b_rot + PI / 2.0)]
	var best := INF
	var best_axis := Vector2.ZERO
	for ax: Vector2 in axes:
		var ra := _radius(a_rot, a_half, ax)
		var rb := _radius(b_rot, b_half, ax)
		var dist := d.dot(ax)
		var overlap := ra + rb - absf(dist)
		if overlap <= 0.0:
			return Vector2.ZERO # a separating axis: no contact
		if overlap < best:
			best = overlap
			best_axis = ax * (1.0 if dist >= 0.0 else -1.0)
	return best_axis * best


static func _radius(rot: float, half: Vector2, axis: Vector2) -> float:
	return half.x * absf(Vector2.from_angle(rot).dot(axis)) + half.y * absf(Vector2.from_angle(rot + PI / 2.0).dot(axis))


## Convenience for vehicle nodes (actors/danfo.gd): position, heading, LENGTH, WIDTH.
static func vehicles(a: Node2D, b: Node2D, pad := 4.0) -> Vector2:
	return obb_mtv(a.position, a.heading, Vector2(a.LENGTH, a.WIDTH) * 0.5 + Vector2(pad, pad), b.position, b.heading, Vector2(b.LENGTH, b.WIDTH) * 0.5 + Vector2(pad, pad))
