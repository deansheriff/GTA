class_name StreetLife
extends Node
## Life on the island (M10): owambe parties to crash (#9), the daily Lagos Wahala event (#10),
## fishing and beach life (#11), the fleet (#12), a home that grows with a generator (#13),
## style that other players see (#14), and the street reputation greetings (#15).
## The phone apps for all of these are in street/street_apps.gd.

var host: StreetHost
var main: Node2D
var apps: StreetApps
var fleet_report := ""
var _owambe_day := -1
var _announced_day := -1
var _event_t := 0.0
var _convoy: Array = []
var _rng := RandomNumberGenerator.new()


func setup(h: StreetHost) -> void:
	host = h
	main = h.main
	_rng.randomize()
	Clock.day_changed.connect(func(_d: int) -> void: fleet_payout())
	apps = StreetApps.new()
	apps.setup(h, self)
	apply_style()


func _lm(id: String) -> Vector2:
	return main.map.landmarks[id]["pos"] if main.map.landmarks.has(id) else Vector2.INF


# ---------- points and prompts ----------

func build_points(map: MapData) -> Array:
	var pts := []
	var yard := _lm(Street.db["impound"]["yard"])
	if yard != Vector2.INF:
		pts.append({ "pos": yard + Vector2(90, 40), "kind": "impound" })
	if _lm("lekki-event-centre") != Vector2.INF:
		pts.append({ "pos": _lm("lekki-event-centre"), "kind": "owambe" })
	for e: Dictionary in Street.db["daily_events"]:
		if _lm(e["where"]) != Vector2.INF:
			pts.append({ "pos": _lm(e["where"]) + Vector2(-60, 30), "kind": "daily", "event": e["id"] })
	var canoes := 0
	for p in map.props:
		if p.kind == "canoe":
			canoes += 1
			if canoes % 2 == 1:
				pts.append({ "pos": p.pos, "kind": "fish" })
		elif p.kind == "fish-baskets":
			pts.append({ "pos": p.pos, "kind": "fishsell" })
	if _lm("oshodi-market") != Vector2.INF:
		pts.append({ "pos": _lm("oshodi-market") + Vector2(60, -30), "kind": "fishsell" })
	return pts


func _fish_count() -> int:
	var n := 0
	for k: Dictionary in Street.db["fish"]["kinds"]:
		n += int(Life.inventory.get("fish-" + String(k["id"]), 0))
	return n


func prompt_for(p: Dictionary) -> String:
	match p["kind"]:
		"impound":
			return "Pay impound fee · ₦%s" % Life.fmt_naira(int(Street.db["impound"]["fee"])) if Street.impounded else ""
		"owambe":
			if main.mode != "walking" or _owambe_day == Clock.day() or not _owambe_on():
				return ""
			return "Crash the owambe!"
		"daily":
			var e := daily_event()
			if e.is_empty() or e["id"] != p["event"] or Street.daily.get("stage", "") in ["done", "runs"] or not _event_hours(e):
				return ""
			return "Today's wahala: %s" % e["name"]
		"fish":
			return "Go fishing (canoe ₦%s)" % Life.fmt_naira(int(Street.db["fish"]["canoe_rent"])) if main.mode == "walking" else ""
		"fishsell":
			return "Sell your fish (%d)" % _fish_count() if _fish_count() > 0 and main.mode == "walking" else ""
	return ""


func use(p: Dictionary) -> bool:
	match p["kind"]:
		"impound":
			if Life.spend(int(Street.db["impound"]["fee"]), "Impound release fee"):
				Street.impounded = false
				main.hud.toast("Bus released. \"Drive with sense next time.\"")
			return true
		"owambe":
			_owambe()
			return true
		"daily":
			_start_event()
			return true
		"fish":
			_fish()
			return true
		"fishsell":
			_sell_fish()
			return true
	return false


func tick(dt: float) -> void:
	_tick_daily(dt)


# ---------- owambe (#9) ----------

func _owambe_on() -> bool:
	return Clock.weekday() in ["Fri", "Sat", "Sun"] and Clock.hour() >= 16 and Clock.hour() < 23


func _owambe() -> void:
	_owambe_day = Clock.day()
	var dressed := Street.outfit in ["agbada", "owambe", "ankara"]
	if not dressed:
		var c := await host.ask("The bouncer", "\"Where your aso-ebi? Who invited you?\"", [
			["bribe", "\"Roger\" him ₦2,000", Life.can_afford(2000)],
			["cousin", "\"I'm the groom's cousin from abroad\""],
			["leave", "Leave"],
		])
		match c:
			"bribe":
				Life.spend(2000, "Owambe bouncer")
			"cousin":
				if _rng.randf() > 0.35 + Life.level("charisma") * 0.06 + Street.rep / 400.0:
					main.hud.toast("\"From abroad? With Oshodi accent?\" Thrown out!")
					Street.add_rep(-1.0)
					return
				main.hud.toast("\"Ah, welcome o! Sit with the family!\"")
			_:
				return
	else:
		main.hud.toast("Correct aso-ebi. The bouncer waves you in like family.")
	# Spray and dance.
	var spray := 2000
	if Life.spend(spray, "Spraying money at the owambe"):
		var res: Dictionary = await main.story.story_minigame("spray", { "title": "Spray the celebrants!", "beats": 14, "bpm": 104 })
		Life.restore("fun", 20.0)
		if int(res.get("score", 0)) >= 70:
			Street.add_rep(2.0)
			main.hud.toast("The MC: \"Who is this big spender?!\" The crowd cheers.")
	# Then the jollof.
	var heist: Dictionary = await main.story.story_minigame("heist", { "need": 6 })
	if heist.get("caught", false):
		Street.add_rep(-3.0)
		if Life.hero == "tunde":
			Life.stats["bp"] = minf(100.0, float(Life.stats.get("bp", 20.0)) + 12.0)
		main.hud.toast("The caterer chased you out with a ladle!")
		Street.post_gist("owambe", "%s was chased out of an owambe for stealing jollof!" % Street._me())
	else:
		Life.restore("hunger", 60.0)
		Life.restore("fun", 10.0)
		Street.count("owambe_crashed")
		main.hud.toast("Party jollof! Belle full. Nobody suspects a thing.", true)
		Street.post_gist("owambe", "%s crashed an owambe in Lekki and ate the jollof!" % Street._me())


# ---------- daily Lagos Wahala (#10) ----------

func daily_event() -> Dictionary:
	var list: Array = Street.db["daily_events"]
	if list.is_empty():
		return {}
	if int(Street.daily.get("day", -1)) != Clock.day():
		Street.daily = { "day": Clock.day(), "id": list[Clock.day() % list.size()]["id"], "stage": "new" }
	for e: Dictionary in list:
		if e["id"] == Street.daily["id"]:
			return e
	return {}


func _event_hours(e: Dictionary) -> bool:
	return Clock.hour() >= int(e["hours"][0]) and Clock.hour() < int(e["hours"][1])


func _tick_daily(dt: float) -> void:
	var e := daily_event()
	if e.is_empty():
		return
	if _event_hours(e) and _announced_day != Clock.day() and Street.daily.get("stage") == "new" and not host.story_busy():
		_announced_day = Clock.day()
		Sound.sfx("notify")
		main.hud.toast("LAGOS WAHALA: %s" % e["name"])
		host.ticker(e["text"], 10.0)
		Street.post_gist("event", "Today's Lagos Wahala: %s" % e["name"])
	if Street.daily.get("stage") != "runs":
		return
	_event_t -= dt
	if _event_t <= 0.0 or not _event_hours(e):
		Street.daily["stage"] = "failed"
		main._set_waypoint(Vector2.INF)
		main.hud.toast("Time up! %s: someone else handled it." % e["name"])
		return
	if e["id"] == "convoy":
		for c: Node2D in _convoy:
			if is_instance_valid(c) and c.position.distance_to(main.player.position if main.mode == "walking" else main.danfo.position) < 380.0:
				_finish_event(e, "You filmed the convoy! The clip is everywhere.")
				Street.post_gist("event", "%s filmed the celebrity convoy in Lekki. Viral!" % Street._me())
				if Life.hero == "kc":
					Life.stats["hype"] = minf(1000.0, float(Life.stats.get("hype", 0.0)) + 40.0)
				return
		return
	var spots: Array = Street.daily["spots"]
	var i := int(Street.daily["i"])
	var focus: Vector2 = main.player.position if main.mode == "walking" else main.danfo.position
	var spot := Vector2(spots[i][0], spots[i][1])
	if focus.distance_to(spot) < 110.0:
		i += 1
		Street.daily["i"] = i
		Sound.sfx("tap", 1.2)
		if i >= spots.size():
			_finish_event(e, "%s: done! The area is grateful." % e["name"])
			return
		main._set_waypoint(Vector2(spots[i][0], spots[i][1]))
		main.hud.toast("%d / %d done. Next one!" % [i, spots.size()])


func _start_event() -> void:
	var e := daily_event()
	var base := _lm(e["where"])
	Street.daily["stage"] = "runs"
	Street.daily["i"] = 0
	_event_t = 150.0
	main.hud.toast(e["text"])
	match e["id"]:
		"convoy":
			_spawn_convoy(base)
			Street.daily["spots"] = []
		"blackout":
			var d: Dictionary = main.map.district_at(base)
			var t := Clock.minutes % 1440
			main._outages.append({ "start": t, "end": t + 120, "rich": true, "district": String(d.get("id", "")) })
			Sound.sfx("power_off")
			Street.daily["spots"] = _spots_around(base, 3, 420.0)
		_:
			Street.daily["spots"] = _spots_around(base, 3, 300.0)
	var spots: Array = Street.daily["spots"]
	if not spots.is_empty():
		main._set_waypoint(Vector2(spots[0][0], spots[0][1]))


func _spots_around(base: Vector2, n: int, r: float) -> Array:
	var out := []
	var tries := 0
	while out.size() < n and tries < 60:
		tries += 1
		var p := base + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(r * 0.6, r)
		if not main.map.is_blocked(p):
			out.append([p.x, p.y])
	return out


func _spawn_convoy(near: Vector2) -> void:
	_convoy.clear()
	var best := ""
	var bd := INF
	for id in main.map.road_nodes:
		var d: float = (main.map.road_nodes[id] as Vector2).distance_to(near)
		if d < bd and not (main.map.road_graph.get(id, []) as Array).is_empty():
			bd = d
			best = id
	if best == "":
		return
	var nb: String = main.map.road_graph[best][0]
	for i in 4:
		var v: Dictionary = main.traffic.spawn_on(best, nb, 40.0 + i * 160.0, "car")
		(v["node"] as Node2D).set_kind("car", Color("#1a1a1a"))
		(v["node"] as Node2D).refresh_art()
		(v["node"] as Node2D).get_children().map(func(c: Node) -> void: if c is Sprite2D: c.self_modulate = Color(0.25, 0.25, 0.28))
		_convoy.append(v["node"])
	Sound.sfx("siren", 1.1)
	main._set_waypoint(main.map.road_nodes[best])


func _finish_event(e: Dictionary, text: String) -> void:
	Street.daily["stage"] = "done"
	var reward := int(e["reward"])
	Life.earn(reward, "Lagos Wahala: %s" % e["name"])
	Street.add_rep(4.0)
	Street.count("daily_done")
	main._set_waypoint(Vector2.INF)
	Sound.sfx("success")
	main.hud.toast("%s +₦%s" % [text, Life.fmt_naira(reward)], true)


# ---------- fishing (#11) ----------

func _fish() -> void:
	var rent := int(Street.db["fish"]["canoe_rent"])
	if not Life.spend(rent, "Canoe rent"):
		return
	var has_net := Life.has_item("fishing-net")
	var res: Dictionary = await main.story.story_minigame("fishing", { "casts": 3 })
	var caught := int(res.get("caught", 0)) + (1 if has_net and int(res.get("caught", 0)) > 0 else 0)
	var names := []
	for i in caught:
		var k := _roll_fish()
		Life.add_item("fish-" + String(k["id"]))
		names.append(k["name"])
	Life.restore("fun", 8.0)
	if caught == 0:
		main.hud.toast("No fish today. The lagoon dey vex.")
	else:
		main.hud.toast("Caught: %s%s." % [", ".join(PackedStringArray(names)), " (the net got an extra)" if has_net else ""])


func _roll_fish() -> Dictionary:
	var kinds: Array = Street.db["fish"]["kinds"]
	var total := 0
	for k: Dictionary in kinds:
		total += int(k["weight"])
	var r := _rng.randi_range(1, total)
	for k: Dictionary in kinds:
		r -= int(k["weight"])
		if r <= 0:
			return k
	return kinds[0]


func _sell_fish() -> void:
	var total := 0
	var n := 0
	for k: Dictionary in Street.db["fish"]["kinds"]:
		var id := "fish-" + String(k["id"])
		var c := int(Life.inventory.get(id, 0))
		if c > 0:
			total += c * int(int(k["price"]) / Street.price_k())
			n += c
			Life.inventory.erase(id)
	if n == 0:
		return
	Life.earn(total, "Sold %d fish" % n)
	Street.count("fish_sold", n)
	main.hud.toast("Sold %d fish for ₦%s. \"Fresh from the lagoon!\"" % [n, Life.fmt_naira(total)])


# ---------- fleet (#12) ----------

func buy_bus(slogan: String, colour: String) -> String:
	var cfg: Dictionary = Street.db["fleet"]
	if Street.fleet.size() >= int(cfg["max_buses"]):
		return "The motor park only has space for %d of your buses." % int(cfg["max_buses"])
	if not Life.spend(int(int(cfg["bus_price"]) * Street.price_k()), "Bought a danfo"):
		return "Money no reach."
	Street.fleet.append({ "id": "bus-%d" % Time.get_ticks_msec(), "name": "Bus %d" % (Street.fleet.size() + 2), "slogan": slogan, "colour": colour, "driver": {}, "route": "", "condition": 100.0, "earned": 0 })
	Street.record("buses_owned", Street.fleet.size() + 1)
	Street.post_gist("fleet", "%s just bought another danfo: \"%s\"." % [Street._me(), slogan])
	main.hud.celebrate_moment("NEW BUS IN THE FLEET", "\"%s\"" % slogan)
	Street.changed.emit()
	return "New bus! Hire a driver and give it a route."


## Three driver candidates today (the same three all day).
func candidates() -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = Clock.day() * 31 + 5
	var names: Array = Street.db["fleet"]["driver_names"]
	var out := []
	for i in 3:
		var honesty := snappedf(r.randf_range(0.25, 1.0), 0.05)
		var skill := snappedf(r.randf_range(0.3, 1.0), 0.05)
		out.append({ "name": names[r.randi() % names.size()], "honesty": honesty, "skill": skill, "wage": int(800 + skill * 1800) / 100 * 100 })
	return out


func hire(bus: Dictionary, driver: Dictionary) -> String:
	if Street.rep < -40.0:
		return "No driver wants to work for an area menace. Fix your reputation."
	bus["driver"] = driver.duplicate()
	if String(bus.get("route", "")) == "":
		var routes: Array = main.jobs.db["danfo_routes"]
		bus["route"] = routes[Street.fleet.find(bus) % routes.size()]["id"]
	Street.changed.emit()
	return "%s is now driving %s." % [driver["name"], bus["name"]]


func repair_bus(bus: Dictionary) -> String:
	var cost := int((100.0 - float(bus["condition"])) * 120.0 * Street.price_k())
	if cost <= 0:
		return "It's in good shape."
	if not Life.spend(cost, "Fleet repairs"):
		return "Money no reach (₦%s)." % Life.fmt_naira(cost)
	bus["condition"] = 100.0
	Street.changed.emit()
	return "Fixed for ₦%s." % Life.fmt_naira(cost)


## Every morning: what each bus brought in (and what went wrong).
func fleet_payout() -> void:
	if Street.fleet.is_empty() or Street.fleet_day == Clock.day():
		return
	Street.fleet_day = Clock.day()
	var cfg: Dictionary = Street.db["fleet"]
	var r := RandomNumberGenerator.new()
	r.seed = Clock.day() * 977
	var total := 0
	var notes := []
	for bus: Dictionary in Street.fleet:
		var d: Dictionary = bus.get("driver", {})
		if d.is_empty():
			notes.append("%s: no driver." % bus["name"])
			continue
		bus["condition"] = maxf(0.0, float(bus["condition"]) - 3.0)
		if r.randf() < (1.0 - float(d["honesty"])) * 0.12:
			notes.append("%s: %s ran off with yesterday's money!" % [bus["name"], d["name"]])
			bus["driver"] = {}
			continue
		if r.randf() < 0.08 * (1.3 - float(d["skill"])):
			bus["condition"] = maxf(0.0, float(bus["condition"]) - 25.0)
			notes.append("%s: small accident. Condition down." % bus["name"])
		var gross := float(cfg["daily_base"]) * (0.6 + 0.6 * float(d["skill"])) * (float(bus["condition"]) / 100.0) * Street.fare_k
		var declared := int(gross * (0.75 + 0.25 * float(d["honesty"])))
		var net := declared - int(d["wage"]) - int(cfg["maintenance"])
		bus["earned"] = int(bus.get("earned", 0)) + net
		total += net
		notes.append("%s (%s): ₦%s" % [bus["name"], d["name"], Life.fmt_naira(net)])
	if total > 0:
		Life.earn(total, "Fleet returns")
	elif total < 0:
		Life.spend(mini(-total, Life.money), "Fleet costs")
	fleet_report = "Day %d fleet report: ₦%s total.\n%s" % [Clock.day(), Life.fmt_naira(total), "\n".join(PackedStringArray(notes))]
	main.hud.toast("Fleet returns: ₦%s. (Phone > Fleet)" % Life.fmt_naira(total))
	main.hud.phone.set_badge("Fleet", 1)
	Street.changed.emit()


# ---------- home (#13) ----------

func upgrade_home() -> String:
	var homes: Array = Street.db["home"]
	if Street.home_tier >= homes.size() - 1:
		return "You already live in a duplex. Na you be landlord now."
	var next: Dictionary = homes[Street.home_tier + 1]
	if not Life.spend(int(int(next["price"]) * Street.price_k()), "Moved to: %s" % next["name"]):
		return "Money no reach."
	Street.home_tier += 1
	if Street.home_tier >= 3:
		Street.count("duplex")
	Street.post_gist("home", "%s moved into a %s!" % [Street._me(), next["name"]])
	main.hud.celebrate_moment("NEW HOUSE", next["name"])
	Street.changed.emit()
	return "Welcome to your %s! %s" % [next["name"], next["note"]]


func buy_generator(tier: int) -> String:
	var gens: Array = Street.db["generators"]
	if tier <= Street.generator or tier >= gens.size():
		return ""
	if not Life.spend(int(int(gens[tier]["price"]) * Street.price_k()), "Bought: %s" % gens[tier]["name"]):
		return "Money no reach."
	Street.generator = tier
	Street.count("generator")
	main.hud.celebrate_moment("NEPA, DO YOUR WORST", gens[tier]["name"])
	Street.changed.emit()
	return "%s installed. NEPA, do your worst." % gens[tier]["name"]


func buy_diesel(litres: int) -> String:
	var cost := int(litres * 950 * Street.price_k())
	if Street.gen_fuel + litres > 30.0:
		return "The jerrycans are full (30 L)."
	if not Life.spend(cost, "Diesel for the generator"):
		return "Money no reach."
	Street.gen_fuel += litres
	Street.changed.emit()
	return "+%d L diesel." % litres


## Called after Life.sleep(): a better home rests you better; a blackout without a generator
## means heat and mosquitoes all night.
func after_sleep(minutes: int) -> String:
	var home := Street.home_info()
	var gen := Street.generator_info()
	var hours := minutes / 60.0
	Life.restore("hygiene", float(home["hygiene"]))
	var dark: bool = main._in_outage(main.player.position)
	if not dark:
		return ""
	var power := 0.0
	if Street.generator > 0:
		var need := float(gen["fuel_per_hour"]) * hours
		if need <= 0.0 or Street.gen_fuel >= need:
			Street.gen_fuel = maxf(0.0, Street.gen_fuel - need)
			power = float(gen["power"])
		elif Street.gen_fuel > 0.0:
			power = float(gen["power"]) * Street.gen_fuel / need
			Street.gen_fuel = 0.0
	var penalty := (1.0 - power) * 25.0 / float(home["sleep"])
	Life.needs["energy"] = clampf(Life.needs["energy"] - penalty, 0.0, 100.0)
	Street.changed.emit()
	if power >= 0.99:
		return "NEPA took light, but your generator hummed all night."
	if power > 0.0:
		return "The generator ran out of diesel at midnight. Half a night's sleep."
	return "NEPA took light. Heat and mosquitoes all night. (A generator would help.)"


# ---------- style (#14) ----------

## Headwear and colours shown on you, and sent to other players.
func style_look() -> Dictionary:
	var caps := { "jersey": "#2f8a52", "conductor": "#1d1d1d", "agbada": "#efe8d6", "owambe": "#76418a", "ankara": "#c96f24" }
	var look := { "outfit": Street.outfit }
	if caps.has(Street.outfit):
		look["cap"] = caps[Street.outfit]
	var paint := String(Street.paint.get("colour", ""))
	if paint != "":
		look["bus"] = paint
	var sl := (Street.db["slogans"] as Array).find(Street.paint.get("slogan", ""))
	if sl >= 0:
		look["sl"] = str(sl)
	if host.online and host.online.crew_tag != "":
		look["crew"] = host.online.crew_tag
	return look


func apply_style() -> void:
	var look := style_look()
	var p: Node2D = main.player
	p.style = look
	p.outfit_tint = Color(Street.outfit_look().get("shirt", "#00000000")) if Life.hero == "tunde" and Street.outfit_look().has("shirt") else Color(0, 0, 0, 0)
	p.queue_redraw()
	host.care.apply_paint()
	Net.send_look(main._look_to_wire(p.look))


## Reputation: how people greet you when you talk to them.
func greeting() -> String:
	var lines := {
		"Street legend": ["Ah! Oga mi! Respect!", "Na you be the legend wey everybody dey talk about!"],
		"Respected": ["Good person! How you dey?", "Ah, my friend. Welcome."],
		"Nobody send you": ["Hmm. How far?", "Yes? Wetin you want?"],
		"Known wahala": ["You again? Abeg no cause wahala here.", "Make you no start o."],
		"Area menace": ["Ehn! Everybody, hide your phone!", "Abeg comot for my front."],
	}
	return host.pick(lines[Street.rep_label()])
