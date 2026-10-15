class_name VehicleCare
extends Node
## Fuel, damage and repairs (M9 #1) plus crash feedback (#21).
##  - Driving burns fuel; an empty tank leaves the bus sputtering at walking pace.
##  - Crashes dent the bus: dents and scratches show, a loose bumper swings, smoke pours out,
##    and past 60% damage the bus slows; past 85% it limps.
##  - Fill up at the PetroNaija station or a roadside jerrycan seller; fix it at the Mushin
##    mechanic or a vulcanizer stand (cheaper, small patches only). Stranded? Call one by phone.
##  - Story missions never strand you: fuel stops draining at 30% and damage doesn't slow the bus.

const FUEL_PER_PX := 100.0 / 90000.0 # a full tank is about seven island crossings

var host: StreetHost
var main: Node2D
var wear: _Wear
var _dry_warned := false
var _smoke_t := 0.0


func setup(h: StreetHost) -> void:
	host = h
	main = h.main
	wear = _Wear.new()
	main.danfo.add_child(wear)
	apply_paint()


func apply_paint() -> void:
	var c := String(Street.paint.get("colour", ""))
	main.danfo.set_paint(Color(c) if c != "" else Color(0, 0, 0, 0))
	wear.slogan = String(Street.paint.get("slogan", ""))
	wear.queue_redraw()


func tick(dt: float) -> void:
	var d: Node2D = main.danfo
	if host.hustles.renting():
		d.limit = INF # a rented keke/okada: not your bus's fuel or dents
		wear.visible = false
		return
	wear.visible = true
	var safe := host.story_busy()
	if main.mode == "driving" and not main.story.interior.active:
		var floor_k := 30.0 if safe else 0.0
		if Street.fuel > floor_k:
			Street.fuel = maxf(floor_k, Street.fuel - absf(d.speed) * dt * FUEL_PER_PX)
		if Street.fuel <= 0.0 and not _dry_warned:
			_dry_warned = true
			Street.count("ran_dry")
			main.hud.toast("Fuel don finish! The bus is crawling. Find fuel or call a jerrycan boy (phone > Garage).")
		elif Street.fuel > 0.0:
			_dry_warned = false
		if Street.fuel < 12.0 and Street.fuel > 0.0 and int(Time.get_ticks_msec() / 1000) % 40 == 0 and _smoke_t <= 0.0:
			main.hud.toast("Fuel light don on. %d%% left." % int(Street.fuel))
	d.limit = INF if safe else Street.bus_limit()
	# Smoke from the engine (rear) when the bus is hurting.
	_smoke_t -= dt
	if Street.damage >= 40.0 and _smoke_t <= 0.0:
		_smoke_t = lerpf(0.5, 0.12, (Street.damage - 40.0) / 60.0)
		var rear: Vector2 = d.position - Vector2.from_angle(d.heading) * d.LENGTH * 0.45
		host.fx.smoke(rear + Vector2(randf_range(-8, 8), -20), (Street.damage - 40.0) / 60.0)
	wear.update(dt, d)


## A crash at `impact` px/s at `at`. Returns the damage taken.
func hit(impact: float, at: Vector2) -> float:
	var dmg := clampf((impact - 90.0) / 28.0, 0.5, 18.0)
	Street.damage = minf(100.0, Street.damage + dmg)
	Street.count("crashes")
	host.fx.pop(["GBAM!", "KPOW!", "GBOSA!", "WAHALA!"][randi() % 4], at, Color("#e0a91c"), 40 + int(minf(24.0, dmg * 2.0)))
	host.fx.debris(at, main.danfo.BODY, 6 + int(dmg))
	wear.knock(impact)
	if Street.damage >= 85.0:
		main.hud.toast("The bus is limping! Get to a mechanic.")
	elif Street.damage >= 60.0 and Street.damage - dmg < 60.0:
		main.hud.toast("Engine don dey knock. Bus slower until you fix am.")
	Street.changed.emit()
	return dmg


# ---------- services ----------

## Service points: the fuel station, the mechanic, roadside jerrycans and vulcanizers.
func build_points(map: MapData) -> Array:
	var pts := []
	if map.landmarks.has("petronaija-station"):
		pts.append({ "pos": map.landmarks["petronaija-station"]["pos"], "kind": "fuel", "label": "PetroNaija" })
	if map.landmarks.has("mushin-mechanic"):
		pts.append({ "pos": map.landmarks["mushin-mechanic"]["pos"], "kind": "mechanic", "label": "Mushin mechanic" })
	var k := 0
	for p in map.props:
		if p.kind == "tyres":
			k += 1
			if k % 2 == 0:
				pts.append({ "pos": p.pos, "kind": "vulcanizer", "label": "Vulcanizer" })
		elif p.kind == "umbrella" and p.seed % 9 == 0:
			pts.append({ "pos": p.pos, "kind": "jerrycan", "label": "Jerrycan fuel" })
	return pts


func prompt_for(p: Dictionary) -> String:
	var v: Dictionary = Street.db["vehicle"]
	match p["kind"]:
		"fuel", "jerrycan":
			var need := 100.0 - Street.fuel
			if need < 2.0:
				return ""
			var per: int = v["fuel_price"] if p["kind"] == "fuel" else v["jerrycan_price"]
			return "Buy fuel · ₦%s" % Life.fmt_naira(Street.fuel_cost(need, per))
		"mechanic":
			if Street.damage < 1.0:
				return ""
			return "Fix the bus · ₦%s" % Life.fmt_naira(Street.repair_cost(Street.damage, v["repair_per_point"]))
		"vulcanizer":
			if Street.damage < 1.0:
				return ""
			var pts := minf(Street.damage, float(v["vulcanizer_max"]))
			return "Patch it up · ₦%s" % Life.fmt_naira(Street.repair_cost(pts, v["vulcanizer_per_point"]))
	return ""


func use(p: Dictionary) -> void:
	var v: Dictionary = Street.db["vehicle"]
	match p["kind"]:
		"fuel", "jerrycan":
			var need := 100.0 - Street.fuel
			var per: int = v["fuel_price"] if p["kind"] == "fuel" else v["jerrycan_price"]
			var cost := Street.fuel_cost(need, per)
			if not Life.can_afford(cost):
				# Buy what you can.
				need = floorf(float(Life.money) / (per * Street.price_k()))
				cost = Street.fuel_cost(need, per)
			if need < 1.0 or not Life.spend(cost, "Fuel"):
				main.hud.toast("Money no reach for fuel.")
				return
			Street.fuel = minf(100.0, Street.fuel + need)
			if p["kind"] == "jerrycan" and randf() < 0.12:
				Street.damage = minf(100.0, Street.damage + 6.0)
				main.hud.toast("Jerrycan fuel: adulterated! The engine coughs.")
			else:
				main.hud.toast("Tank full. Baba God dey!" if Street.fuel >= 99.0 else "Fuel: %d%%." % int(Street.fuel))
			Sound.sfx("cash")
		"mechanic", "vulcanizer":
			var pts := Street.damage if p["kind"] == "mechanic" else minf(Street.damage, float(v["vulcanizer_max"]))
			var per: int = v["repair_per_point"] if p["kind"] == "mechanic" else v["vulcanizer_per_point"]
			var cost := Street.repair_cost(pts, per)
			if not Life.spend(cost, "Bus repairs"):
				return
			Street.damage = maxf(0.0, Street.damage - pts)
			Street.count("repairs")
			wear.reset_bumper()
			main.hud.toast("Panel beater don work am. Bus %d%% healthy." % int(100.0 - Street.damage))
			Sound.sfx("success")
	Street.changed.emit()


## Phone: stranded somewhere? Someone comes to you, for a fee.
func call_jerrycan() -> String:
	var v: Dictionary = Street.db["vehicle"]
	var cost := int(v["jerrycan_callout"]) + Street.fuel_cost(25.0, v["jerrycan_price"])
	if Street.fuel >= 60.0:
		return "Your tank is fine."
	if not Life.spend(cost, "Jerrycan delivery"):
		return "Money no reach (₦%s)." % Life.fmt_naira(cost)
	Street.fuel = minf(100.0, Street.fuel + 25.0)
	return "A boy on an okada brought 25%% fuel. ₦%s." % Life.fmt_naira(cost)


func call_mechanic() -> String:
	var v: Dictionary = Street.db["vehicle"]
	var pts := minf(Street.damage, 30.0)
	if pts < 1.0:
		return "Nothing to fix."
	var cost := int(v["mechanic_callout"]) + Street.repair_cost(pts, v["repair_per_point"])
	if not Life.spend(cost, "Roadside mechanic"):
		return "Money no reach (₦%s)." % Life.fmt_naira(cost)
	Street.damage -= pts
	Street.count("repairs")
	wear.reset_bumper()
	return "A roadside mechanic patched it: −%d damage. ₦%s." % [int(pts), Life.fmt_naira(cost)]


## Drawn on top of the bus: dents and scratches, a swinging bumper and the paint slogan.
class _Wear extends Node2D:
	var slogan := ""
	var remote := false # another player's bus: their slogan only (their damage isn't sent)
	var bumper_ang := 0.0
	var bumper_vel := 0.0
	var _last_speed := 0.0
	var _drawn_damage := -1

	func _ready() -> void:
		z_index = 1
		position = Vector2(0, -10)

	func knock(impact: float) -> void:
		bumper_vel += randf_range(-1.0, 1.0) * impact / 60.0

	func reset_bumper() -> void:
		bumper_ang = 0.0
		bumper_vel = 0.0
		queue_redraw()

	func _process(_d: float) -> void:
		if remote:
			queue_redraw()

	func update(dt: float, d: Node2D) -> void:
		var accel: float = (d.speed - _last_speed) / maxf(dt, 0.001)
		_last_speed = d.speed
		if Street.damage >= 50.0 and d.kind == "danfo":
			# A loose bumper on a hinge: springs back, swings with braking and corners.
			bumper_vel += (-(bumper_ang - 0.55) * 18.0 - bumper_vel * 2.2 + accel * 0.004) * dt
			bumper_ang = clampf(bumper_ang + bumper_vel * dt, -0.6, 1.3)
			queue_redraw()
		elif int(Street.damage / 10.0) != _drawn_damage:
			_drawn_damage = int(Street.damage / 10.0)
			queue_redraw()

	func _draw() -> void:
		var d: Node2D = get_parent()
		if d == null or d.kind != "danfo":
			return
		if remote:
			_draw_slogan(d)
			return
		var h: float = d.heading
		var fwd := Vector2.from_angle(h)
		var side := Vector2(-fwd.y, fwd.x)
		var l: float = d.LENGTH * 0.5
		var w: float = d.WIDTH * 0.5
		# Dents and scratches: more of them as damage grows (fixed spots, so they don't jump around).
		var n := int(Street.damage / 9.0)
		var r := RandomNumberGenerator.new()
		r.seed = 77
		for i in n:
			var p := fwd * r.randf_range(-l * 0.8, l * 0.8) + side * r.randf_range(-w * 0.8, w * 0.8)
			var a := r.randf() * TAU
			draw_line(p - Vector2.from_angle(a) * 6.0, p + Vector2.from_angle(a) * 6.0, Color(0.1, 0.07, 0.04, 0.75), 2.0)
			draw_circle(p + side * 3.0, 3.0, Color(0.2, 0.15, 0.08, 0.35))
		# The loose rear bumper, hanging from one corner.
		if Street.damage >= 50.0:
			var hinge := -fwd * (l + 2.0) + side * w * 0.9
			var dir := (-side).rotated(bumper_ang)
			draw_line(hinge, hinge + dir * w * 1.9, Color("#1d1611"), 8.0)
			draw_line(hinge, hinge + dir * w * 1.9, d.BODY.darkened(0.15), 5.0)
			draw_circle(hinge, 3.0, Color("#1d1611"))
		_draw_slogan(d)

	func _draw_slogan(d: Node2D) -> void:
		var h: float = d.heading
		var fwd := Vector2.from_angle(h)
		var l: float = d.LENGTH * 0.5
		# Slogan on the back of the roof.
		if slogan != "":
			var font := ThemeDB.fallback_font
			# Along the bus, kept upright so it always reads left to right.
			draw_set_transform(-fwd * l * 0.62 + Vector2(0, -6), h if cos(h) >= 0.0 else h + PI)
			var size := font.get_string_size(slogan, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
			draw_string_outline(font, Vector2(-size.x * 0.5, 4), slogan, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, Color("#1d1611"))
			draw_string(font, Vector2(-size.x * 0.5, 4), slogan, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#f1e6c8"))
			draw_set_transform(Vector2.ZERO)
