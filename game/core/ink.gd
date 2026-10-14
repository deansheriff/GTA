class_name Ink
extends RefCounted
## Drawing helpers for the ink-and-paint placeholder style: filled shapes with thick dark outlines.

const COLOR := Color("#1d1611")
const W := 2.6 # default outline width


static func poly(ci: CanvasItem, pts: PackedVector2Array, fill: Color, width: float = W) -> void:
	ci.draw_colored_polygon(pts, fill)
	if width > 0.0:
		var closed := pts.duplicate()
		closed.append(pts[0])
		ci.draw_polyline(closed, COLOR, width, true)


static func rect(ci: CanvasItem, r: Rect2, fill: Color, width: float = W) -> void:
	poly(ci, PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), fill, width)


static func ellipse_points(center: Vector2, radii: Vector2, segments: int = 24, rot: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y).rotated(rot))
	return pts


static func ellipse(ci: CanvasItem, center: Vector2, radii: Vector2, fill: Color, width: float = W, rot: float = 0.0) -> void:
	poly(ci, ellipse_points(center, radii, 24, rot), fill, width)


static func circle(ci: CanvasItem, center: Vector2, r: float, fill: Color, width: float = W) -> void:
	ci.draw_circle(center, r, fill)
	if width > 0.0:
		ci.draw_arc(center, r, 0.0, TAU, 28, COLOR, width, true)


## Soft contact shadow cast to the bottom-right (sun from the top-left).
static func shadow(ci: CanvasItem, center: Vector2, radii: Vector2, alpha: float = 0.32) -> void:
	ci.draw_colored_polygon(ellipse_points(center + Vector2(radii.x * 0.18, radii.y * 0.25), radii, 20), Color(0.06, 0.04, 0.03, alpha))
	ci.draw_colored_polygon(ellipse_points(center + Vector2(radii.x * 0.1, radii.y * 0.12), radii * 0.7, 20), Color(0.06, 0.04, 0.03, alpha * 0.6))


## Deterministic random generator for stable per-object variation.
static func rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r
