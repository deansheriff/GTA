class_name StreetApps
extends RefCounted
## Phone apps for the street systems: Garage (fuel, repairs, paint), Fleet, Home, Style,
## Awards and Gist (the Lagos Gist feed, local + online).

var host: StreetHost
var life: StreetLife
var phone: Control


func setup(h: StreetHost, l: StreetLife) -> void:
	host = h
	life = l
	phone = h.main.hud.phone
	phone.add_app("Garage", _garage)
	phone.add_app("Fleet", _fleet)
	phone.add_app("Home", _home)
	phone.add_app("Style", _style)
	phone.add_app("Awards", _awards)
	phone.add_app("Gist", _gist)


func _l(text: String, size := 15, col := Color("#f1e6c8")) -> Label:
	return phone._label(text, size, col)


func _h(text: String) -> void:
	phone._label(text, 13, Color("#e0a91c"))


func _b(text: String, cb: Callable, parent: Node = null, enabled := true) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.disabled = not enabled
	b.pressed.connect(cb)
	(parent if parent else phone._screen).add_child(b)
	return b


func _row() -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 6)
	phone._screen.add_child(r)
	return r


func _say(text: String) -> void:
	if text != "":
		host.main.hud.toast(text)


# ---------- Garage ----------

func _garage() -> void:
	phone._clear("Garage")
	_h("BABA GOD DEY")
	phone._bar("Fuel", Street.fuel)
	phone._bar("Condition", 100.0 - Street.damage)
	if Street.impounded:
		_l("Impounded! Pay the fee at the %s." % Street.db["impound"]["name"], 15, Color("#ff7a5c"))
	_l("Fill up at PetroNaija (Mushin) or a jerrycan seller. Fix it at the Mushin mechanic or a roadside vulcanizer.", 13)
	_b("Call a jerrycan boy (25%% fuel, ₦%s callout)" % Life.fmt_naira(int(Street.db["vehicle"]["jerrycan_callout"])), func() -> void:
		_say(host.care.call_jerrycan())
		_garage())
	_b("Call a roadside mechanic (₦%s callout)" % Life.fmt_naira(int(Street.db["vehicle"]["mechanic_callout"])), func() -> void:
		_say(host.care.call_mechanic())
		_garage())
	_h("PAINT AND SLOGAN")
	for p: Dictionary in Street.db["paints"]:
		var paint: Dictionary = p
		var price := int(int(p["price"]) * Street.price_k())
		var current := String(Street.paint.get("colour", "")) == String(p["colour"])
		_b("%s%s" % [p["name"], " (current)" if current else (" · ₦%s" % Life.fmt_naira(price) if price > 0 else "")], func() -> void:
			if price > 0 and not Life.spend(price, "Bus paint: %s" % paint["name"]):
				return
			Street.paint["colour"] = paint["colour"]
			life.apply_style()
			_garage(), null, not current)
	var opt := OptionButton.new()
	var slogans: Array = Street.db["slogans"]
	for i in slogans.size():
		opt.add_item(slogans[i])
		if slogans[i] == Street.paint.get("slogan", ""):
			opt.select(i)
	opt.item_selected.connect(func(i: int) -> void:
		Street.paint["slogan"] = slogans[i]
		life.apply_style())
	phone._screen.add_child(opt)


# ---------- Fleet ----------

func _fleet() -> void:
	phone._clear("Fleet")
	var cfg: Dictionary = Street.db["fleet"]
	_l("You own %d bus%s (Baba God Dey + %d)." % [Street.fleet.size() + 1, "es" if Street.fleet.size() > 0 else "", Street.fleet.size()], 15)
	if life.fleet_report != "":
		_l(life.fleet_report, 13, Color("#9fd38a"))
	for bus: Dictionary in Street.fleet:
		var b: Dictionary = bus
		_h("%s · \"%s\"" % [bus["name"], bus["slogan"]])
		var d: Dictionary = bus.get("driver", {})
		_l("Driver: %s · Route: %s · Condition %d%% · Earned ₦%s" % [d.get("name", "none"), bus.get("route", "-"), int(bus["condition"]), Life.fmt_naira(int(bus.get("earned", 0)))], 13)
		var r := _row()
		_b("Repair", func() -> void:
			_say(life.repair_bus(b))
			_fleet(), r)
		if d.is_empty():
			_b("Hire a driver", func() -> void: _hire(b), r)
		else:
			_b("Sack %s" % d["name"], func() -> void:
				b["driver"] = {}
				_fleet(), r)
	if Street.fleet.size() < int(cfg["max_buses"]):
		_h("BUY ANOTHER DANFO · ₦%s" % Life.fmt_naira(int(int(cfg["bus_price"]) * Street.price_k())))
		var opt := OptionButton.new()
		for s: String in Street.db["slogans"]:
			opt.add_item(s)
		phone._screen.add_child(opt)
		_b("Buy it", func() -> void:
			_say(life.buy_bus(opt.get_item_text(opt.selected), ""))
			_fleet())


func _hire(bus: Dictionary) -> void:
	phone._clear("Hire a driver")
	_l("Today's candidates at the motor park. Honest drivers bring all the money home; skilled ones bring more of it and crash less.", 13)
	for c: Dictionary in life.candidates():
		var cand: Dictionary = c
		_h(c["name"])
		_l("Honesty %s · Skill %s · Wage ₦%s/day" % ["★".repeat(int(round(float(c["honesty"]) * 5))), "★".repeat(int(round(float(c["skill"]) * 5))), Life.fmt_naira(int(c["wage"]))], 13)
		_b("Hire %s" % c["name"], func() -> void:
			_say(life.hire(bus, cand))
			_fleet())


# ---------- Home ----------

func _home() -> void:
	phone._clear("Home")
	var home := Street.home_info()
	var gen := Street.generator_info()
	_h("WHERE YOU LIVE")
	_l("%s\n%s" % [home["name"], home["note"]], 15)
	var homes: Array = Street.db["home"]
	if Street.home_tier < homes.size() - 1:
		var next: Dictionary = homes[Street.home_tier + 1]
		_b("Move to: %s · ₦%s" % [next["name"], Life.fmt_naira(int(int(next["price"]) * Street.price_k()))], func() -> void:
			_say(life.upgrade_home())
			_home())
	_h("GENERATOR")
	_l("%s · Diesel: %.0f L" % [gen["name"], Street.gen_fuel], 15)
	var gens: Array = Street.db["generators"]
	for i in range(Street.generator + 1, gens.size()):
		var tier := i
		_b("Buy %s · ₦%s" % [gens[i]["name"], Life.fmt_naira(int(int(gens[i]["price"]) * Street.price_k()))], func() -> void:
			_say(life.buy_generator(tier))
			_home())
	if Street.generator in [1, 2]:
		_b("Buy 10 L diesel · ₦%s" % Life.fmt_naira(int(10 * 950 * Street.price_k())), func() -> void:
			_say(life.buy_diesel(10))
			_home())
	_l("NEPA takes light at night? Without a generator you sleep in the heat with the mosquitoes.", 12, Color(1, 1, 1, 0.6))


# ---------- Style ----------

func _style() -> void:
	phone._clear("Style")
	_l("Other players see your headwear, your bus paint and slogan, and your crew tag.", 13)
	_h("OUTFITS")
	for o: Dictionary in Street.db["outfits"]:
		var outfit: Dictionary = o
		var owned: bool = o["id"] in Street.outfits_owned
		var wearing: bool = Street.outfit == o["id"]
		var price := int(int(o["price"]) * Street.price_k())
		_b("%s%s" % [o["name"], " (wearing)" if wearing else ("" if owned else " · ₦%s" % Life.fmt_naira(price))], func() -> void:
			if not owned:
				if not Life.spend(price, "Clothes: %s" % outfit["name"]):
					return
				Street.outfits_owned.append(outfit["id"])
			Street.outfit = outfit["id"]
			life.apply_style()
			_style(), null, not wearing)
	_h("PHONES")
	for p: Dictionary in Street.db["phones"]:
		var ph: Dictionary = p
		var current: bool = Street.phone == p["id"]
		var price := int(int(p["price"]) * Street.price_k())
		_b("%s · battery ×%.1f%s" % [p["name"], float(p["battery"]), " (yours)" if current else (" · ₦%s" % Life.fmt_naira(price) if price > 0 else "")], func() -> void:
			if price > 0 and not Life.spend(price, "Phone: %s" % ph["name"]):
				return
			Street.phone = ph["id"]
			phone_skin()
			_style(), null, not current)


func phone_skin() -> void:
	var body: PanelContainer = phone.get_child(1) if phone.get_child_count() > 1 else null
	if body:
		var sb := (body.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
		sb.bg_color = Color(Street.phone_info()["skin"])
		body.add_theme_stylebox_override("panel", sb)


# ---------- Awards ----------

func _awards() -> void:
	phone._clear("Awards")
	var list := Street.achievement_list()
	var done := list.filter(func(a: Dictionary) -> bool: return a["done"]).size()
	_l("%d / %d unlocked · Street rep: %s (%d)" % [done, list.size(), Street.rep_label(), int(Street.rep)], 15)
	for a: Dictionary in list:
		_l("%s %s" % ["★" if a["done"] else "☆", a["title"]], 15, Color("#e0a91c") if a["done"] else Color("#f1e6c8"))
		_l("%s  (%d/%d)" % [a["text"], int(a["progress"]), int(a["goal"])], 12, Color(1, 1, 1, 0.6))


# ---------- Gist ----------

func _gist() -> void:
	phone._clear("Lagos Gist")
	_l("What the street is saying. Your fights, crashes, wins and awards post here (and to players in your area when you're online).", 12, Color(1, 1, 1, 0.6))
	host.online.gist_online_into(phone)
	_h("YOUR GIST")
	if Street.gist_log.is_empty():
		_l("Nothing yet. Go and cause small wahala.", 13)
	for e: Dictionary in Street.gist_log.slice(0, 25):
		var day := int(e["t"]) / 1440 + 1
		_l("Day %d · %s" % [day, e["text"]], 13)
