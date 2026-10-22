class_name Guide3D
extends Control
## On-screen guidance (D-032), drawn over the 3D view:
##  - the objective: an arrow at the screen edge pointing to it when it's off screen, a marker over
##    it when it's on screen, and the distance;
##  - prompts in the world: a small tag over what you can use (the nearest vehicle's ENTER, a
##    stall, a pump);
##  - where damage came from: a red wedge at the edge of the screen towards whoever hit you.

var world # Street3D
var _hits: Array = [] # [world position, seconds left]
var _font: Font


func setup(w) -> void:
	world = w
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UiStyle.display()


func hit_from(pos: Vector3) -> void:
	_hits.append([pos, 1.1])


func _process(delta: float) -> void:
	for h: Array in _hits.duplicate():
		h[1] = float(h[1]) - delta
		if float(h[1]) <= 0.0:
			_hits.erase(h)
	queue_redraw()


func _draw() -> void:
	if world == null or not world._built or world.in_menu or world.cam == null:
		return
	var cam: Camera3D = world.cam
	var vp := get_viewport_rect().size
	var cb := bool(Settings.get_pref("colorblind", false))
	var gold := Color("#4fb3ff") if cb else Color("#f6d04d")
	# The objective.
	var t: Variant = world.run.target() if is_instance_valid(world.run) else null
	if t != null and not world.hud.dialogue.visible:
		var tp: Vector3 = t
		var d: float = world.focus().distance_to(tp)
		var behind := cam.is_position_behind(tp + Vector3(0, 1.5, 0))
		var sp := cam.unproject_position(tp + Vector3(0, 1.5, 0))
		var margin := 70.0
		var on_screen := not behind and sp.x > margin and sp.y > margin and sp.x < vp.x - margin and sp.y < vp.y - margin
		var label := "%d m" % int(d) if d < 1000.0 else "%.1f km" % (d / 1000.0)
		if on_screen:
			_diamond(sp, 11.0, gold)
			draw_string(_font, sp + Vector2(-30, -20), label, HORIZONTAL_ALIGNMENT_CENTER, 60, 18, Color.WHITE)
		else:
			var c := vp * 0.5
			var dir := (sp - c).normalized()
			if behind:
				dir = -dir
			if dir == Vector2.ZERO:
				dir = Vector2.DOWN
			var edge := c + dir * minf((vp.x * 0.5 - margin) / maxf(absf(dir.x), 0.001), (vp.y * 0.5 - margin) / maxf(absf(dir.y), 0.001))
			var side := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([edge + dir * 18.0, edge - dir * 10.0 + side * 13.0, edge - dir * 4.0, edge - dir * 10.0 - side * 13.0]), gold)
			draw_string(_font, edge - dir * 34.0 + Vector2(-30, 6), label, HORIZONTAL_ALIGNMENT_CENTER, 60, 17, Color.WHITE)
	# Prompts in the world.
	if world.ride == null and world.prompt_text == "" and not world.hud.dialogue.visible and not world.combat.active:
		var best: Vehicle3D = null
		var bd: float = Street3D.ENTER_RANGE + 0.5
		for v in world.vehicles:
			var dd: float = v.position.distance_to(world.player.position) - v.length * 0.35
			if dd < bd and not v.is_wreck:
				bd = dd
				best = v
		if best and not cam.is_position_behind(best.position + Vector3(0, 2.6, 0)):
			_tag(cam.unproject_position(best.position + Vector3(0, 2.6, 0)), "ENTER")
	elif world.prompt_text != "" and world.prompt_at != null and not cam.is_position_behind(world.prompt_at):
		_tag(cam.unproject_position(world.prompt_at), world.prompt_text)
	# Where the hits came from: in the camera's frame, ahead is up the screen, behind is down.
	var inv: Basis = cam.global_transform.basis.inverse()
	for h: Array in _hits:
		var local: Vector3 = inv * ((h[0] as Vector3) - world.focus())
		var dir := Vector2(local.x, local.z)
		if dir.length() < 0.01:
			continue
		var c := vp * 0.5
		var r := minf(vp.x, vp.y) * 0.36
		var a0 := dir.angle() - 0.35
		var alpha := clampf(float(h[1]), 0.0, 1.0)
		draw_arc(c, r, a0, a0 + 0.7, 16, Color(0.95, 0.15, 0.1, 0.75 * alpha), 14.0)


func _diamond(p: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), col)
	draw_polyline(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0), p + Vector2(0, -r)]), UiStyle.INK, 2.0)


func _tag(p: Vector2, text: String) -> void:
	var w := 18.0 + text.length() * 10.5
	var r := Rect2(p - Vector2(w * 0.5, 16), Vector2(w, 26))
	draw_rect(r, Color(0.08, 0.06, 0.04, 0.78))
	draw_rect(r, Color("#e0a91c"), false, 2.0)
	draw_string(_font, r.position + Vector2(0, 19), text, HORIZONTAL_ALIGNMENT_CENTER, w, 16, Color("#fff4d6"))
