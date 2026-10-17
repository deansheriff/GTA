class_name GarageSys
extends Node
## Cars you own, park and steal (M14, owner: "a Garage where they can park their cars… the GTA
## mechanism where users can steal cars").
##  - The main vehicle node (main.danfo) is whatever you're driving; Street.current says what it
##    is. Every other vehicle you've used is parked where you left it (a solid car in the world,
##    saved). Baba God Dey is always either what you drive or parked somewhere (minimap marker).
##  - Steal: walk up to almost any vehicle in traffic and take it. The driver is dragged out and
##    either runs off shouting "Ole!", fights you for it, or just stands there in shock. Area heat
##    and street reputation take the hit; the car is flagged stolen.
##  - Garage at your home: park cars there (1–5 slots, by your house), take one out any time.
##  - Mushin chop shop: sell a stolen car, or respray it so it's clean.
##  - Story missions always use Baba God Dey; you're put back in it when one starts.

const STEAL_REACH := 95.0
const MAX_ABANDONED := 3 # stolen cars left lying around get towed beyond this

var host: StreetHost
var main: Node2D
var nodes: Array = [] # parked vehicle nodes (meta "spec")
var garage_pos := Vector2.INF
var _rng := RandomNumberGenerator.new()


func setup(h: StreetHost) -> void:
	host = h
	main = h.main
	_rng.randomize()
	_find_garage()
	reapply_current()
	for p: Dictionary in Street.parked:
		_spawn_parked(p["spec"], Vector2(float(p["x"]), float(p["y"])), float(p.get("h", 0.0)))
	# Baba God Dey must exist somewhere: if it's neither driven nor parked, it waits at home.
	if not Street.driving_baba() and _baba_node() == null:
		_spawn_parked(Street.BABA.duplicate(), garage_pos + Vector2(0, 120), 0.0)
	_save_parked()


func _db() -> Dictionary:
	return Street.db.get("vehicles", {})


func kind_info(kind: String) -> Dictionary:
	return _db().get("kinds", {}).get(kind, { "name": kind, "top": 380, "chop": 10000 })


## The garage sits by the hero's home, on open ground.
func _find_garage() -> void:
	var home: Vector2 = main.map.landmarks.get(Life.home, main.map.landmarks.values()[0])["pos"]
	for r: float in [140.0, 200.0, 260.0, 340.0]:
		for i in 8:
			var p := home + Vector2.from_angle(i * TAU / 8.0 + 0.4) * r
			if not main.map.body_blocked(p, 0.0, Vector2(70, 32)):
				garage_pos = p
				return
	garage_pos = home + Vector2(140, 60)


# ---------- the main vehicle ----------

## Make main.danfo look and drive like Street.current (after a load, a rental, a swap).
func reapply_current() -> void:
	var spec: Dictionary = Street.current
	var d: Node2D = main.danfo
	var col := String(spec.get("colour", ""))
	d.set_kind(String(spec.get("kind", "danfo")), Color(col) if col != "" else Color(0, 0, 0, 0))
	d.refresh_art()
	d.max_road = float(kind_info(d.kind)["top"])
	if Street.driving_baba():
		host.care.apply_paint()
	else:
		d.set_paint(Color(0, 0, 0, 0))
		host.care.wear.slogan = ""
		host.care.wear.queue_redraw()
	d.queue_redraw()


## Drive `spec` from now on: the vehicle you were using is left parked where it stands.
func switch_to(spec: Dictionary, pos: Vector2, heading: float) -> void:
	var d: Node2D = main.danfo
	var old: Dictionary = Street.current.duplicate()
	old["fuel"] = Street.fuel
	old["damage"] = Street.damage
	if main.mode == "driving":
		d.speed = 0.0
		main._enter_exit()
	_spawn_parked(old, d.position, d.heading)
	Street.current = spec.duplicate()
	Street.fuel = float(spec.get("fuel", 80.0))
	Street.damage = float(spec.get("damage", 0.0))
	d.position = pos
	d.heading = heading
	d.speed = 0.0
	reapply_current()
	_tow_extras()
	_save_parked()


func _spawn_parked(spec: Dictionary, pos: Vector2, heading: float) -> Node2D:
	var n: Node2D = preload("res://actors/danfo.gd").new()
	var col := String(spec.get("colour", ""))
	n.set_kind(String(spec.get("kind", "danfo")), Color(col) if col != "" else Color(0, 0, 0, 0))
	n.position = pos
	n.heading = heading
	n.material = main.painted_mat
	n.set_meta("spec", spec)
	main.streamer.add_child(n)
	if String(spec.get("id", "")) == "baba":
		var c := String(Street.paint.get("colour", ""))
		n.set_paint(Color(c) if c != "" else Color(0, 0, 0, 0))
		var wr: Node2D = VehicleCare._Wear.new()
		wr.remote = true
		wr.slogan = String(Street.paint.get("slogan", ""))
		n.add_child(wr)
	nodes.append(n)
	return n


func _remove_parked(n: Node2D) -> void:
	nodes.erase(n)
	n.queue_free()
	_save_parked()


func _baba_node() -> Node2D:
	for n: Node2D in nodes:
		if String((n.get_meta("spec") as Dictionary).get("id", "")) == "baba":
			return n
	return null


## Stolen cars you've dumped around town get towed after a while (only the newest few stay).
func _tow_extras() -> void:
	var junk := nodes.filter(func(n: Node2D) -> bool: return String((n.get_meta("spec") as Dictionary).get("id", "")) != "baba")
	while junk.size() > MAX_ABANDONED:
		_remove_parked(junk.pop_front())


func _save_parked() -> void:
	Street.parked = []
	for n: Node2D in nodes:
		Street.parked.append({ "spec": n.get_meta("spec"), "x": n.position.x, "y": n.position.y, "h": n.heading })


## Back into Baba God Dey (missions, danfo runs, after selling or losing a car).
func back_to_baba(leave_current := true) -> void:
	if Street.driving_baba():
		return
	var b := _baba_node()
	var pos: Vector2 = b.position if b else garage_pos + Vector2(0, 120)
	var h: float = b.heading if b else 0.0
	var spec: Dictionary = b.get_meta("spec") if b else Street.BABA.duplicate()
	if b:
		_remove_parked(b)
	if leave_current:
		switch_to(spec, pos, h)
	else:
		# The current car is gone (sold, confiscated, taken back): just become Baba where it waits.
		if main.mode == "driving":
			main.danfo.speed = 0.0
			main._enter_exit()
		Street.current = spec.duplicate()
		Street.fuel = float(spec.get("fuel", 80.0))
		Street.damage = float(spec.get("damage", 0.0))
		main.danfo.position = pos
		main.danfo.heading = h
		reapply_current()
		_save_parked()


# ---------- per frame ----------

func tick(_dt: float) -> void:
	# Story missions are written for Baba God Dey.
	if main.story.mission_running() and not Street.driving_baba():
		back_to_baba()
		main.hud.toast("Story time: you're back in Baba God Dey.")
	# Parked cars are solid for your vehicle too.
	if main.mode == "driving":
		var d: Node2D = main.danfo
		for n: Node2D in nodes:
			var mtv := Collide.vehicles(d, n, 2.0)
			if mtv != Vector2.ZERO:
				d.position += mtv
				d.speed *= -0.2
	main.traffic.solids = nodes


# ---------- prompts ----------

func prompt(focus: Vector2) -> Dictionary:
	if host.story_busy() or host.hustles.renting():
		return {}
	if main.mode == "walking":
		# Your own parked cars first.
		for n: Node2D in nodes:
			if n.position.distance_to(focus) < 100.0:
				var spec: Dictionary = n.get_meta("spec")
				if String(spec.get("id", "")) == "baba" and Life.hero != "tunde":
					continue
				return { "kind": "parked", "node": n, "label": "Enter %s" % spec.get("name", kind_info(spec["kind"])["name"]) }
		if focus.distance_to(garage_pos) < 110.0:
			return { "kind": "garage_open", "label": "Garage (%d/%d)" % [Street.garage.size(), Street.garage_slots()] }
		if not main._near_danfo():
			var v := _steal_target(focus)
			if not v.is_empty():
				return { "kind": "steal", "v": v, "label": "Steal the %s!" % kind_info(v["kind"])["name"] }
	elif main.mode == "driving":
		if main.danfo.position.distance_to(garage_pos) < 170.0 and not Street.driving_baba():
			return { "kind": "garage_park", "label": "Park in garage" if Street.garage.size() < Street.garage_slots() else "Garage full" }
		if Street.current.get("stolen", false) and main.map.landmarks.has("mushin-mechanic") and main.danfo.position.distance_to(main.map.landmarks["mushin-mechanic"]["pos"]) < 200.0:
			return { "kind": "chop", "label": "Chop shop" }
	return {}


func _steal_target(focus: Vector2) -> Dictionary:
	var best := {}
	var bd := STEAL_REACH
	for v: Dictionary in main.traffic.vehicles:
		if v.has("fleet"):
			continue # not your own buses
		var n: Node2D = v["node"]
		var d := n.position.distance_to(focus)
		if d < bd and absf(float(v["speed"])) < 140.0:
			bd = d
			best = v
	return best


func act(p: Dictionary) -> void:
	match p["kind"]:
		"parked":
			var n: Node2D = p["node"]
			var spec: Dictionary = n.get_meta("spec")
			var pos := n.position
			var h: float = n.heading
			_remove_parked(n)
			switch_to(spec, pos, h)
			main.player.position = pos + Vector2(0, 40)
			main._enter_exit()
		"garage_open":
			_garage_menu()
		"garage_park":
			_park_in_garage()
		"steal":
			_steal(p["v"])
		"chop":
			_chop_shop()


# ---------- stealing ----------

func _steal(v: Dictionary) -> void:
	if not main.traffic.vehicles.has(v):
		return
	var n: Node2D = v["node"]
	var kind := String(v["kind"])
	var spec := { "id": "car-%d" % Time.get_ticks_msec(), "kind": kind, "colour": "#" + n.BODY.to_html(false) if kind == "car" else "", "stolen": true, "fuel": _rng.randf_range(25.0, 80.0), "damage": _rng.randf_range(0.0, 25.0), "name": "the stolen %s" % kind_info(kind)["name"] }
	var pos := n.position
	var h: float = n.heading
	main.traffic.vehicles.erase(v)
	n.queue_free()
	switch_to(spec, pos, h)
	# Dragged out: the driver lands beside the car.
	var driver: Node2D = preload("res://actors/story_npc.gd").new()
	driver.setup("angry-driver", "angry-driver")
	var looks: Array = StreetClash.DRIVER_LOOKS.get(kind, [0, 2, 4])
	driver.use_sprite("characters/drivers-a.png", looks[_rng.randi() % looks.size()])
	driver.material = main.painted_mat
	driver.position = pos + Vector2.from_angle(h + PI / 2.0) * 70.0
	main.streamer.add_child(driver)
	main.player.position = pos + Vector2(0, 40)
	main._enter_exit()
	Sound.sfx("crash", 0.8)
	host.fx.pop("CARJACK!", pos + Vector2(0, -80), Color("#ff7a5c"), 34, 1.2)
	Street.count("cars_stolen")
	Street.add_heat(1.2)
	Street.add_rep(-3.0)
	Street.post_gist("theft", "%s jacked a %s in %s!" % [Street._me(), kind_info(kind)["name"], main._district])
	var line := host.pick(_db().get("thief_lines", ["Thief!"]))
	driver.say(line, 4.0)
	host.reactions.crashed(pos)
	var roll := _rng.randf()
	if (roll < 0.3 and kind not in ["okada", "keke"]) or roll < 0.12:
		# He fights for it.
		main.danfo.speed = 0.0
		main._enter_exit()
		main.hud.toast("The driver wants his car back!")
		var res: Dictionary = await main.story.story_minigame("fight", { "opponent": "Angry driver", "opponent_node": driver, "intro": "\"%s\"" % line })
		if int(res.get("score", 0)) > 50:
			main.hud.toast("You won. The car is yours… for now.", true)
			Street.count("fights_won")
		else:
			main.hud.toast("He beat you and drove off in his car.")
			Life.restore("energy", -15.0)
			back_to_baba(false)
	else:
		main.hud.toast("You took the %s. \"%s\"" % [kind_info(kind)["name"], line])
	# The driver runs off after a moment.
	await get_tree().create_timer(5.0).timeout
	if is_instance_valid(driver):
		driver.queue_free()


# ---------- the garage ----------

func _park_in_garage() -> void:
	if Street.garage.size() >= Street.garage_slots():
		main.hud.toast("Garage full (%d slots). A bigger house has a bigger garage." % Street.garage_slots())
		return
	var spec: Dictionary = Street.current.duplicate()
	spec["fuel"] = Street.fuel
	spec["damage"] = Street.damage
	Street.garage.append(spec)
	if Street.garage.size() >= Street.garage_slots():
		Street.record("garage_full", 1)
	main.hud.toast("Parked %s in the garage." % spec.get("name", "the car"))
	Sound.sfx("tap")
	# You walk out of the garage; your main vehicle is Baba God Dey again, wherever it's parked.
	back_to_baba(false)
	main.player.position = garage_pos + Vector2(0, 70)
	main.player.visible = true
	Street.changed.emit()


func _garage_menu() -> void:
	var opts := []
	for i in Street.garage.size():
		var s: Dictionary = Street.garage[i]
		opts.append(["take%d" % i, "Take out %s%s" % [s.get("name", kind_info(s["kind"])["name"]), " (stolen)" if s.get("stolen", false) else ""]])
	opts.append(["close", "Close"])
	var body := "Your garage: %d of %d slots used. %s" % [Street.garage.size(), Street.garage_slots(), "Empty. Drive a car here to park it." if Street.garage.is_empty() else ""]
	var c := await host.ask("Garage", body, opts)
	if not c.begins_with("take"):
		return
	var i := int(c.trim_prefix("take"))
	if i < 0 or i >= Street.garage.size():
		return
	var spec: Dictionary = Street.garage[i]
	Street.garage.remove_at(i)
	var out := garage_pos + Vector2(0, 40)
	switch_to(spec, out, 0.0)
	main.player.position = out + Vector2(0, 40)
	main._enter_exit()
	Street.changed.emit()


# ---------- the chop shop ----------

func _chop_shop() -> void:
	var kind := String(Street.current.get("kind", "car"))
	var price := int(int(kind_info(kind)["chop"]) * (1.0 - Street.damage / 200.0))
	var respray := int(_db().get("respray", 3000))
	var c := await host.ask("Mushin chop shop", "\"Nice %s. Wetin you want?\"" % kind_info(kind)["name"], [
		["sell", "Sell it (₦%s)" % Life.fmt_naira(price)],
		["respray", "Respray it clean (₦%s)" % Life.fmt_naira(respray), Life.can_afford(respray)],
		["no", "Not today"],
	])
	match c:
		"sell":
			Life.earn(price, "Chop shop: %s" % kind_info(kind)["name"])
			Street.count("chopped")
			main.hud.toast("Sold for ₦%s. No questions asked." % Life.fmt_naira(price))
			back_to_baba(false)
		"respray":
			Life.spend(respray, "Respray")
			Street.current["stolen"] = false
			Street.current["colour"] = ["#2f6f99", "#c8432f", "#2f8a52", "#1d1d1d", "#ece4d2"][_rng.randi() % 5] if kind == "car" else ""
			Street.current["name"] = "your %s" % kind_info(kind)["name"]
			reapply_current()
			main.hud.toast("New paint, new plates. It's clean now.")
