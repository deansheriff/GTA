extends Node2D
## Placeholder street props in top-down 3/4 with ink outlines. Node origin = ground contact point.

const K := Layout.HEIGHT_K

var kind := ""
var seed := 0
var smoke: CPUParticles2D


func setup(spec: Layout.PropSpec) -> void:
	kind = spec.kind
	seed = spec.seed
	position = spec.pos
	if kind == "generator":
		smoke = CPUParticles2D.new()
		smoke.position = Vector2(10, -22)
		smoke.amount = 14
		smoke.lifetime = 1.8
		smoke.direction = Vector2(0.3, -1)
		smoke.spread = 20.0
		smoke.gravity = Vector2(6, -14)
		smoke.initial_velocity_min = 8.0
		smoke.initial_velocity_max = 18.0
		smoke.scale_amount_min = 3.0
		smoke.scale_amount_max = 7.0
		smoke.color = Color(0.35, 0.34, 0.36, 0.45)
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1, 1, 1, 0.7))
		ramp.set_color(1, Color(1, 1, 1, 0.0))
		smoke.color_ramp = ramp
		smoke.emitting = false
		add_child(smoke)


func set_generator_running(on: bool) -> void:
	if smoke:
		smoke.emitting = on


## Top of the pole in local coords (for wires).
func wire_anchor() -> Vector2:
	return Vector2(0, -170.0 * K)


func _draw() -> void:
	var r := Ink.rng(seed)
	match kind:
		"umbrella":
			Ink.shadow(self, Vector2(10, 4), Vector2(46, 18), 0.28)
			Ink.rect(self, Rect2(-20, -26, 40, 22), Color("#7a5536"), 2.0) # table
			Ink.rect(self, Rect2(-6, -34, 12, 8), Color("#222222"), 1.6) # POS machine
			draw_line(Vector2(0, -4), Vector2(0, -78 * K), Ink.COLOR, 3.0)
			var cols: Array = [Color("#a8382c"), Color("#efe6d2")] if seed % 2 == 0 else [Color("#2f6f99"), Color("#e0a91c")]
			var c := Vector2(0, -80 * K - 8)
			for i in 8:
				var a0 := TAU * i / 8.0
				var a1 := TAU * (i + 1) / 8.0
				Ink.poly(self, PackedVector2Array([c, c + Vector2(cos(a0) * 44, sin(a0) * 30), c + Vector2(cos(a1) * 44, sin(a1) * 30)]), cols[i % 2], 1.6)
			Ink.circle(self, c, 3.0, Color("#dddddd"), 1.2)
		"pole", "transformer":
			Ink.shadow(self, Vector2(18, 2), Vector2(26, 5), 0.25)
			var top := -170.0 * K
			Ink.poly(self, PackedVector2Array([Vector2(-3, 0), Vector2(3, 0), Vector2(2, top), Vector2(-2, top)]), Color("#6b4a30"), 1.6)
			Ink.rect(self, Rect2(-20, top + 6, 40, 4), Color("#4a3322"), 1.4)
			for dx in [-16, 0, 16]:
				Ink.rect(self, Rect2(dx - 2, top, 4, 6), Color("#d6e6f0"), 1.0)
			if kind == "transformer":
				Ink.rect(self, Rect2(-14, top + 28, 28, 26), Color("#7d8a8f"), 2.0)
				draw_string(ThemeDB.fallback_font, Vector2(-14, top + 45), "ELDDC", HORIZONTAL_ALIGNMENT_CENTER, 28, 7, Color("#a8382c"))
		"generator":
			Ink.shadow(self, Vector2(6, 2), Vector2(22, 8), 0.35)
			Ink.poly(self, PackedVector2Array([Vector2(-16, 0), Vector2(16, 0), Vector2(16, -16), Vector2(-16, -16)]), Color("#a8382c"), 2.0)
			Ink.poly(self, PackedVector2Array([Vector2(-16, -16), Vector2(16, -16), Vector2(16, -30), Vector2(-16, -30)]), Color("#d8b032"), 2.0)
			Ink.rect(self, Rect2(-10, -12, 9, 8), Color("#2a2a2a"), 1.2)
			draw_line(Vector2(10, -30), Vector2(10, -36), Ink.COLOR, 3.0)
		"kiosk":
			Ink.shadow(self, Vector2(14, 4), Vector2(48, 16), 0.3)
			Ink.rect(self, Rect2(-40, -46, 80, 46), Color("#2f6f99").lerp(Color("#22806f"), float(seed % 2)), 2.4)
			Ink.rect(self, Rect2(-30, -36, 60, 26), Color("#2a2219"), 1.8)
			for i in 6:
				Ink.rect(self, Rect2(-27 + i * 9.5, -33 + (i % 2) * 6, 7, 9), [Color("#d8b032"), Color("#c96f24"), Color("#efe6d2")][i % 3], 1.0)
			Ink.rect(self, Rect2(-44, -60, 88, 16), Color("#8c9396"), 2.4) # roof seen from above
		"tyres":
			Ink.shadow(self, Vector2(6, 2), Vector2(22, 8), 0.3)
			for i in 4:
				Ink.ellipse(self, Vector2(0, -6 - i * 7), Vector2(17, 8), Color("#242222"), 2.0)
				Ink.ellipse(self, Vector2(0, -6 - i * 7), Vector2(7, 3.5), Color("#3d3a38"), 1.2)
		"mango":
			Ink.shadow(self, Vector2(26, 8), Vector2(62, 26), 0.33)
			Ink.poly(self, PackedVector2Array([Vector2(-6, 0), Vector2(6, 0), Vector2(4, -36), Vector2(-4, -36)]), Color("#5a3d27"), 2.0)
			var leaf := [Color("#3f6a2c"), Color("#4f7a33"), Color("#5d873a"), Color("#35592a")]
			var cc := Vector2(0, -70)
			for i in 9:
				var a := TAU * i / 9.0 + r.randf() * 0.4
				var pos := cc + Vector2(cos(a) * 26, sin(a) * 18) * r.randf_range(0.6, 1.05)
				Ink.circle(self, pos, r.randf_range(18, 26), leaf[i % 4], 2.2)
			Ink.circle(self, cc + Vector2(-6, -6), 22, leaf[2].lightened(0.06), 2.2)
			for i in 6:
				draw_circle(cc + Vector2(r.randf_range(-30, 30), r.randf_range(-24, 20)), 3.0, Color("#c9a23a"))
		"palm":
			Ink.shadow(self, Vector2(30, 8), Vector2(50, 18), 0.3)
			var tip := Vector2(10, -110)
			draw_polyline(PackedVector2Array([Vector2(0, 0), Vector2(8, -50), tip]), Ink.COLOR, 9.0, true)
			draw_polyline(PackedVector2Array([Vector2(0, 0), Vector2(8, -50), tip]), Color("#7a5a3a"), 5.5, true)
			for i in 9:
				var a := TAU * i / 9.0 + 0.2
				var end := tip + Vector2(cos(a) * 52, sin(a) * 30 + 10)
				var side := Vector2(-sin(a), cos(a)) * 9.0
				Ink.poly(self, PackedVector2Array([tip, (tip + end) * 0.5 + side, end, (tip + end) * 0.5 - side * 0.4]), [Color("#4f7a33"), Color("#3f6a2c")][i % 2], 1.8)
