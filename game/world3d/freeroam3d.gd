class_name FreeRoam3D
extends Node3D
## Free roam (D-028): the life between missions.
##  - the daily delivery: the bus's owner wants ₦8,000 a day from the danfo, collected at midnight
##    (Uncle Obi bought the bus; Ọkpụ's boy collects, until Dayo knows who Ọkpụ is);
##  - fuel and repairs: every ride burns fuel; filling stations and mechanics by the main roads;
##  - buying vehicles: the Alaba dealer (and the boat yard at Makoko once you've been to the creeks);
##    what you own waits parked by Mama Àgbà's house;
##  - side jobs at the job boards in the markets: deliveries, okada fares, street fights, carrying a
##    market woman's load;
##  - Respect perks (cheaper roger, cheaper repairs, bigger fares, park boys who lose the police);
##  - NEPA cuts district by district, go-slow at rush hour with hawkers at the window, Mama Àgbà's
##    food stall (its buffs, until Act III), and Radio Gbedu with Uncle Obi's adverts;
##  - after the last mission, the post-game the ending made (kingpin, chairman, or neutral driver).

const DELIVERY := 8000
const TANK := { "okada": 1500, "keke": 2500, "car": 4000, "taxi": 4000, "danfo": 6000, "suv": 7000, "pickup": 5000, "van": 5000, "bus": 9000, "truck": 9000, "tanker": 9000, "speedboat": 8000, "canoe": 0, "ambulance": 6000, "horse": 0 }
const FOR_SALE := [
	["okada", 60000], ["keke", 150000], ["taxi", 350000], ["car", 420000], ["danfo", 800000],
	["pickup", 650000], ["suv", 1200000],
]
const BOATS := [["canoe", 40000], ["speedboat", 900000]]
## Respect perks: [needed, id, name, what it does]
const PERKS := [
	[10, "nod", "Agbero nod", "Checkpoint roger costs a quarter less"],
	[25, "mechanic", "Mechanic's friend", "Repairs cost 30% less"],
	[40, "park", "Park allies", "Park boys help you lose the police (Wanted falls faster)"],
	[60, "oga", "Oga", "Fares pay 15% more"],
	[80, "chairman", "Chairman's word", "Police and task force settle for half"],
]
const HAWKER_GOODS := [
	{ "id": "water", "text": "Pure water (₦50)", "price": 50, "hp": 1 },
	{ "id": "gala", "text": "Gala sausage roll (₦200)", "price": 200, "hp": 2, "stamina": 0.4 },
	{ "id": "plantain", "text": "Plantain chips (₦300)", "price": 300, "hp": 2 },
	{ "id": "credit", "text": "Phone credit (₦500)", "price": 500, "hp": 0 },
	{ "id": "none", "text": "No, thank you", "price": 0, "hp": 0 },
]
const RADIO_DJ := [
	"Radio Gbedu 99.1: your number one Pidgin station. Lagos, how body?",
	"Traffic: Third Mainland is standing still. Ojuelegba is a car park. Patience, my people.",
	"Weather: rain by evening. Low roads in Lekki, take care.",
	"Shout-out to all the danfo drivers hustling since 5am. Una go make am!",
	"NEPA update: light don come for Surulere. Who knows how long.",
	"The DJ says: if your conductor no give you change, collect am with style.",
]
const RADIO_ADS := [
	"ADVERT: \"Okpu Electronics, Alaba International: original phones, original price. Chief Obinna Nwankwo, your brother in business. E no dey spoil!\"",
	"ADVERT: \"Ọkpụ Electronics: generators, TVs, fridges. When NEPA fails you, Ọkpụ never fails you!\"",
	"ADVERT: Uncle Obi's voice: \"Lagos, I dey for you. Come to Alaba and tell them Ọkpụ sent you.\"",
	"ADVERT: \"Mama Put Gold: the jollof that ends arguments.\"",
	"ADVERT: \"Eko Fresh pure water: clean and cold, one naira at a time.\"",
]

var world # Street3D
var owned: Array = [] # vehicle kinds Dayo has bought
var today := 0 # fares earned today (₦)
var debt := 0 # delivery money still owed
var buffs := {} # id -> seconds left: "regen", "stamina", "iroko"
var postgame := "" # the ending's free roam: "staff", "judgment", "judgment_bitter", "japa"
var cut := "" # district id where NEPA has taken light
var stations: Array = [] # {pos, kind: "fuel"|"mechanic"|"dealer"|"boats"|"jobs"|"stall", name}
var radio_on := true
var _cut_t := 120.0
var _radio_t := 0.0
var _radio_i := 0
var _hawker: Person3D
var _still_t := 0.0
var _hawk_cool := 0.0
var _mama: Person3D
var _stall_sign: Label3D
var _respect_wave_t := 0.0
var _side_running := false
var found := {} # Lagos Stories and stashes found (Explore3D)
var board_rep := {} # job board -> how many good jobs it remembers
var _streak := 0
var _prompt_owner := "" # which station set the current prompt
var _rng := RandomNumberGenerator.new()


func setup(w) -> void:
	world = w
	_rng.seed = 99
	Clock.day_changed.connect(_on_day)
	on_region()


## The map changed: rebuild the stations for it (only Lagos has the economy's services).
func on_region() -> void:
	for c in get_children():
		c.queue_free()
	stations.clear()
	_mama = null
	_hawker = null
	cut = ""
	if world.region != "lagos":
		return
	var map: MapData = world.map
	var spots: Array = []
	for r: Dictionary in map.roads:
		if String(r["class"]) == "street":
			continue
		var pts: PackedVector2Array = r["points"]
		for i in pts.size() - 1:
			if pts[i].distance_to(pts[i + 1]) > 1100.0:
				spots.append([pts[i], pts[i + 1]])
	var k := 0
	for s: Array in spots:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		var p := a.lerp(b, 0.35) + side * 150.0
		var ok := true
		for st: Dictionary in stations:
			if Terrain3D.w(p).distance_to(st["pos"]) < 160.0:
				ok = false
		if not ok or world.is_water_at(Terrain3D.w(p)):
			continue
		var kind := "fuel" if k % 3 != 2 else "mechanic"
		_station(Terrain3D.w(p), kind, -dir.angle())
		k += 1
		if k >= 9:
			break
	for spec: Array in [["alaba-market", "dealer", [8, 6]], ["makoko-jetty", "boats", [4, -3]], ["oshodi-market", "jobs", [6, 4]], ["computer-village", "jobs", [5, 5]], ["obalende-motor-park", "jobs", [5, -5]], ["ojuelegba-buka", "jobs", [4, 4]]]:
		if map.landmarks.has(spec[0]):
			_station(world.resolve({ "at": "landmark:" + String(spec[0]), "offset": spec[2] }), spec[1], 0.0)
	_station(world.resolve({ "at": "landmark:" + String(Life.home), "offset": [-5, 3] }) if map.landmarks.has(Life.home) else world.resolve({ "at": "node:mushin_c", "offset": [6, 6] }), "stall", 0.0)


func _station(pos: Vector3, kind: String, yaw: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	add_child(root)
	var names := { "fuel": "FILLING STATION", "mechanic": "MECHANIC · VULCANIZER", "dealer": "ALABA MOTORS · NEW & TOKUNBO", "boats": "MAKOKO BOAT YARD", "jobs": "JOBS · ASK HERE", "stall": "MAMA ÀGBÀ'S · EWA AGOYIN" }
	match kind:
		"fuel":
			var c: Node3D = world.models.make("canopy", "res://art3d/free/")
			if c:
				var bb := Models3D.aabb(c)
				var s := 9.0 / maxf(bb.size.x, bb.size.z)
				c.scale = Vector3.ONE * s
				c.position = Vector3(-bb.get_center().x * s, -bb.position.y * s, -bb.get_center().z * s)
				root.add_child(c)
			for i in 2:
				var pump := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.6, 1.5, 0.4)
				pump.mesh = bm
				var m := StandardMaterial3D.new()
				m.albedo_color = Color("#2f8a52") if i == 0 else Color("#e0a91c")
				pump.material_override = m
				pump.position = Vector3(-1.6 + i * 3.2, 0.75, 0)
				root.add_child(pump)
		"mechanic", "dealer", "boats":
			for i in 3:
				var t: Node3D = world.models.make("tyres")
				if t:
					Models3D.fit_height(t, 1.0)
					var h := Node3D.new()
					h.add_child(t)
					h.position = Vector3(-2.0 + i * 1.6, 0, -1.5)
					root.add_child(h)
		"jobs":
			var k: Node3D = world.models.make("kiosk")
			if k:
				Models3D.fit_height(k, 2.4)
				root.add_child(k)
		"stall":
			var u: Node3D = world.models.make("umbrella")
			if u:
				Models3D.fit_height(u, 2.6)
				root.add_child(u)
			var tb: Node3D = world.models.make("plastic_table")
			if tb:
				Models3D.fit_height(tb, 0.8)
				var h := Node3D.new()
				h.add_child(tb)
				h.position = Vector3(1.2, 0, 0.6)
				root.add_child(h)
	var l := Label3D.new()
	l.text = names.get(kind, kind)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 48
	l.pixel_size = 0.01
	l.outline_size = 10
	l.modulate = Color("#f6d04d") if kind != "jobs" else Color("#9fe0ff")
	l.position = Vector3(0, 4.2 if kind == "fuel" else 3.2, 0)
	root.add_child(l)
	Models3D.far_cull(root, 110.0)
	if kind == "stall":
		_stall_sign = l
	stations.append({ "pos": pos, "kind": kind, "node": root })


# ---------- every frame ----------

func step(delta: float) -> void:
	for b in buffs.keys():
		buffs[b] = float(buffs[b]) - delta
		if float(buffs[b]) <= 0.0 and b != "iroko" and b != "jerrycan":
			buffs.erase(b)
			world.notify("The food's goodness has worn off.")
	world.player.stamina_k = 0.4 if buffs.has("stamina") else 1.0
	# The jerrycan from a stash: an empty tank gets filled once.
	if buffs.has("jerrycan") and world.ride and world.ride.fuel < 0.08 and int(TANK.get(world.ride.kind, 0)) > 0:
		buffs.erase("jerrycan")
		world.ride.fuel = 1.0
		world.notify("You empty the jerrycan into the tank. Full.")
	if world.in_menu or world.region != "lagos":
		_set_prompt("", Callable())
		return
	_nepa(delta)
	_radio(delta)
	_stall()
	_hawkers(delta)
	_respect_greetings(delta)
	if world.missions.running != "" or _side_running:
		if _prompt_owner != "":
			_set_prompt("", Callable())
		return
	_station_prompts()


func _set_prompt(text: String, cb: Callable, owner := "roam", at: Variant = null) -> void:
	if text == "":
		if _prompt_owner != "":
			world.prompt_text = ""
			world.prompt_cb = Callable()
			world.prompt_at = null
			_prompt_owner = ""
		return
	world.prompt_text = text
	world.prompt_cb = cb
	world.prompt_at = at
	_prompt_owner = owner


func _station_prompts() -> void:
	var f: Vector3 = world.focus()
	var ride: Vehicle3D = world.ride
	for st: Dictionary in stations:
		var d := Vector2(f.x - st["pos"].x, f.z - st["pos"].z).length()
		if d > 7.0:
			continue
		var tag: Vector3 = (st["pos"] as Vector3) + Vector3(0, 2.6, 0)
		match String(st["kind"]):
			"fuel":
				if ride and absf(ride.speed) < 1.0 and ride.fuel < 0.98 and int(TANK.get(ride.kind, 0)) > 0:
					var cost := int(ceil((1.0 - ride.fuel) * int(TANK.get(ride.kind, 4000)) / 50.0)) * 50
					_set_prompt("FUEL ₦%s" % _n(cost), func() -> void: _refuel(cost), "roam", tag)
					return
			"mechanic":
				if ride and absf(ride.speed) < 1.0 and ride.health < 99.0:
					var cost := int((100.0 - ride.health) * 45.0 * (0.7 if perk("mechanic") else 1.0) / 50.0) * 50 + 500
					_set_prompt("REPAIR ₦%s" % _n(cost), func() -> void: _repair(cost), "roam", tag)
					return
			"dealer":
				if ride == null:
					_set_prompt("BUY A RIDE", func() -> void: _shop(FOR_SALE, st["pos"]), "roam", tag)
					return
			"boats":
				if ride == null and Story.done.has("m10"):
					_set_prompt("BUY A BOAT", func() -> void: _shop(BOATS, st["pos"]), "roam", tag)
					return
			"jobs":
				if ride == null or d < 5.0:
					_set_prompt("SIDE JOB", func() -> void: _side_job(st), "roam", tag)
					return
			"stall":
				if ride == null and _stall_open():
					_set_prompt("EAT AT MAMA ÀGBÀ'S", _eat, "roam", tag)
					return
	_set_prompt("", Callable())


# ---------- fuel, repairs, vehicles ----------

func _refuel(cost: int) -> void:
	if world.ride == null:
		return
	if Life.spend(cost, "Fuel for the %s (3D)" % world.ride.kind):
		world.ride.fuel = 1.0
		Sound.sfx("cash")
		world.notify("Tank full. ₦%s." % _n(cost))


func _repair(cost: int) -> void:
	if world.ride == null:
		return
	if Life.spend(cost, "Mechanic: repairs (3D)"):
		world.ride.health = world.ride.hp_max
		Sound.sfx("success")
		world.notify("\"E don set, oga.\" Repaired for ₦%s." % _n(cost))


func _shop(list: Array, at: Vector3) -> void:
	var opts: Array = []
	for it: Array in list:
		opts.append({ "id": it[0], "text": "%s  ₦%s%s" % [String(it[0]).capitalize(), _n(int(it[1])), "  (you own one)" if owned.has(it[0]) else ""] })
	opts.append({ "id": "", "text": "Just looking" })
	var picked: Array = await world.say([{ "who": "story", "text": "\"Oga, which one you like? Na clean tokunbo, no wahala.\"", "choices": opts }])
	if picked.is_empty() or String(picked[0].get("id", "")) == "":
		return
	var kind := String(picked[0]["id"])
	var price := 0
	for it: Array in list:
		if it[0] == kind:
			price = int(it[1])
	if not Life.spend(price, "Bought a %s (3D)" % kind):
		return
	owned.append(kind)
	Sound.sfx("cash")
	var v: Vehicle3D = world.spawn_owned(kind, at + Vector3(4, 0, 4))
	world.notify("The %s is yours. It waits by Mama Àgbà's house whenever you come back." % kind)
	if v:
		world.run.story_target = null


## Owned vehicles parked by the house when you continue a game.
func on_continue() -> void:
	if world.region != "lagos":
		return
	var home: Vector3 = world.home_pos()
	for i in owned.size():
		world.spawn_owned(String(owned[i]), home + Vector3(6 + i * 5.5, 0, 6))


# ---------- the daily delivery ----------

func on_fare_paid() -> void:
	var last: Array = Life.ledger.slice(-1)
	if not last.is_empty():
		var amt := int((last[0] as Dictionary).get("delta", 0))
		if perk("oga") and amt > 0:
			var bonus := int(amt * 0.15)
			Life.earn(bonus, "Oga bonus on fares (3D)")
			amt += bonus
		today += maxi(0, amt)


## The danfo's daily delivery: from the first day on the bus (after the prologue) until it burns at
## the end of Act I; and again in the Japa post-game, driving for a new owner.
func delivery_due() -> bool:
	if postgame != "":
		return postgame == "japa"
	return Story.done.has("p0") and not Story.done.has("m06")


func _on_day(_d: int) -> void:
	if postgame in ["staff", "judgment"]:
		_postgame_income()
	if not delivery_due():
		today = 0
		return
	var owe := DELIVERY + debt
	var paid := mini(owe, int(Life.money))
	if paid > 0:
		Life.spend(paid, "Daily delivery to the bus owner (3D)")
	debt = owe - paid
	if debt > 0:
		Story.add_respect(-2)
		world.notify("Ọkpụ's collector came for the delivery: ₦%s short. \"Oga no go happy.\"" % _n(debt))
	else:
		world.notify("Daily delivery paid to the bus owner's collector: ₦%s." % _n(paid))
	today = 0
	world._save_game()


# ---------- Respect perks ----------

func perk(id: String) -> bool:
	for p: Array in PERKS:
		if p[1] == id:
			return Story.respect >= int(p[0])
	return false


func roger_k() -> float:
	var k := 0.75 if perk("nod") else 1.0
	if perk("chairman"):
		k *= 0.5
	return k


## Wanted fades this much faster (park boys hold the police up).
func wanted_k() -> float:
	return 1.6 if perk("park") else 1.0


func perk_lines() -> Array:
	var out := []
	for p: Array in PERKS:
		out.append("%s %s (Respect %d): %s" % ["✔" if Story.respect >= int(p[0]) else "·", p[2], p[0], p[3]])
	return out


## People who know you greet you in the street.
func _respect_greetings(delta: float) -> void:
	_respect_wave_t -= delta
	if Story.respect < 30 or world.ride != null or _respect_wave_t > 0.0:
		return
	_respect_wave_t = 4.0
	for p: Person3D in world.people:
		if p.position.distance_to(world.player.position) < 3.5 and p.state == Person3D.State.WALK and _rng.randf() < 0.35:
			p.state = Person3D.State.PAUSE
			p.pause_left = 2.0
			p.rotation.y = atan2(world.player.position.x - p.position.x, world.player.position.z - p.position.z)
			Models3D.play(p.ap, "wave", "idle")
			world.notify(["\"Sabi! How far?\"", "\"Na Sabi be this!\"", "\"Oga Sabi, well done o.\""][_rng.randi() % 3])
			return


# ---------- NEPA ----------

func _nepa(delta: float) -> void:
	_cut_t -= delta
	if _cut_t > 0.0:
		return
	var map: MapData = world.map
	if cut == "":
		var d: Dictionary = map.districts[_rng.randi() % map.districts.size()]
		cut = String(d["id"])
		_cut_t = _rng.randf_range(90.0, 200.0)
		world.lights.set_cut(cut)
		if world._dark > 0.3 or _in_cut():
			world.notify("NEPA has taken light in %s." % String(d["name"]))
	else:
		var name := ""
		for d: Dictionary in map.districts:
			if d["id"] == cut:
				name = String(d["name"])
		cut = ""
		_cut_t = _rng.randf_range(120.0, 300.0)
		world.lights.set_cut("")
		if name != "" and world._dark > 0.3:
			world.notify("UP NEPA! Light is back in %s." % name)


func _in_cut() -> bool:
	if cut == "":
		return false
	var f: Vector3 = world.focus()
	return String(world.map.district_at(Vector2(f.x, f.z) / Terrain3D.K).get("id", "")) == cut


func nepa_on() -> bool:
	return not _in_cut()


# ---------- go-slow and hawkers ----------

## AI cruise speed factor here: rush hour clogs the main roads (7-10am, 4-8pm).
func goslow_k(pos: Vector3) -> float:
	if world.region != "lagos":
		return 1.0
	var h := Clock.hour()
	if (h >= 7 and h < 10) or (h >= 16 and h < 20):
		return 0.45
	return 1.0


func _hawkers(delta: float) -> void:
	_hawk_cool = maxf(0.0, _hawk_cool - delta)
	var ride: Vehicle3D = world.ride
	var stopped: bool = ride != null and not ride.on_water and absf(ride.speed) < 1.2 and world._dark < 0.6
	_still_t = _still_t + delta if stopped else 0.0
	if _hawker and is_instance_valid(_hawker):
		if not stopped or ride == null:
			_hawker.queue_free()
			_hawker = null
			if _prompt_owner == "hawker":
				_set_prompt("", Callable())
			return
		var win := ride.position + Vector3(-ride.forward().z, 0, ride.forward().x) * -1.8
		var to := win - _hawker.position
		to.y = 0.0
		if to.length() > 0.3:
			_hawker.position += to.normalized() * minf(1.6 * delta, to.length())
			_hawker.rotation.y = atan2(to.x, to.z)
			Models3D.play(_hawker.ap, "walk", "idle")
		else:
			Models3D.play(_hawker.ap, "talk", "idle")
			if world.missions.running == "" and _prompt_owner == "":
				_set_prompt("BUY FROM HAWKER", _buy_hawker, "hawker")
		return
	if _still_t > 3.0 and _hawk_cool <= 0.0 and world.missions.running == "" and not world.people_keys.is_empty():
		_hawk_cool = 40.0
		var p := Person3D.new()
		add_child(p)
		var key: String = "market_woman" if world.models.has("market_woman", Models3D.CHARS) else String(world.people_keys[0])
		if p.setup(world.models, key, world, Vector2i(int(ride.position.x / 4.0), int(ride.position.z / 4.0)), 4040):
			p.position = ride.position + ride.forward() * 7.0 + Vector3(-ride.forward().z, 0, ride.forward().x) * -2.5
			p.state = Person3D.State.PAUSE
			p.pause_left = 1e9
			_hawker = p
			world.notify("\"Pure water! Gala! Credit!\" A hawker weaves through the go-slow.")
		else:
			p.free()


func _buy_hawker() -> void:
	var picked: Array = await world.say([{ "who": "story", "text": "\"Oga, buy something now! E dey cold!\"", "choices": HAWKER_GOODS }])
	_set_prompt("", Callable())
	if picked.is_empty():
		return
	var g: Dictionary = picked[0]
	if int(g.get("price", 0)) <= 0:
		return
	if Life.spend(int(g["price"]), "Hawker: %s (3D)" % g["id"]):
		world.combat.player_hp = mini(Combat3D.PLAYER_MAX, world.combat.player_hp + int(g.get("hp", 0)))
		world.player.stamina = minf(1.0, world.player.stamina + float(g.get("stamina", 0.0)))
		Sound.sfx("cash")
		world.notify("Bought %s." % String(g["text"]).get_slice(" (", 0).to_lower())
	if _hawker and is_instance_valid(_hawker):
		_hawker.queue_free()
		_hawker = null


# ---------- Mama Àgbà's stall ----------

func _stall_open() -> bool:
	return not Story.done.has("m18")


func _stall() -> void:
	var st: Dictionary = {}
	for s: Dictionary in stations:
		if s["kind"] == "stall":
			st = s
	if st.is_empty():
		return
	var open: bool = _stall_open() and world.missions.running == ""
	if _stall_sign:
		_stall_sign.text = "MAMA ÀGBÀ'S · EWA AGOYIN" if _stall_open() else "CLOSED"
	var near: bool = world.focus().distance_to(st["pos"]) < 60.0
	if open and near and _mama == null:
		var p := Person3D.new()
		add_child(p)
		var key := String(Story.who("mama_agba").get("model", "mama_agba"))
		if world.models.has(key, Models3D.CHARS) and p.setup(world.models, key, world, Vector2i(int(st["pos"].x / 4.0), int(st["pos"].z / 4.0)), 3131):
			p.position = st["pos"] + Vector3(0.6, 0, -0.4)
			p.state = Person3D.State.PAUSE
			p.pause_left = 1e9
			Models3D.play(p.ap, "idle", "")
			_mama = p
		else:
			p.free()
	elif (not open or not near) and _mama != null:
		_mama.queue_free()
		_mama = null


func _eat() -> void:
	var picked: Array = await world.say([{ "who": "mama_agba", "text": "Dayo, my son! You don chop? Sit down.", "choices": [
		{ "id": "ewa", "text": "Ewa agoyin and agege bread (₦600): health back, heal faster" },
		{ "id": "amala", "text": "Amala and ewedu (₦700): run longer" },
		{ "id": "", "text": "Later, Mama" },
	] }])
	if picked.is_empty() or String(picked[0].get("id", "")) == "":
		return
	var id := String(picked[0]["id"])
	var price := 600 if id == "ewa" else 700
	if not Life.spend(price, "Mama Àgbà's food (3D)"):
		return
	if id == "ewa":
		world.combat.player_hp = Combat3D.PLAYER_MAX
		buffs["regen"] = 300.0
		world.notify("Ewa agoyin and agege bread. You feel strong: health heals twice as fast for a while.")
	else:
		world.player.stamina = 1.0
		buffs["stamina"] = 300.0
		world.notify("Amala and ewedu. You could run to Ikorodu: sprinting tires you far less for a while.")
	Sound.sfx("success")


# ---------- side jobs ----------

## A side job from a JOBS board. Kinds: deliveries (one to three drops, some fragile, all against
## the clock), passengers with requests (careful driving, "I'm late", a stop on the way), street
## fights for the traders, and carrying a market woman's load. Each board remembers how well you've
## done: a streak of good jobs pays a bonus and raises what that board pays; a failure costs Respect.
func _side_job(st: Dictionary) -> void:
	var board := "%d,%d" % [int(st["pos"].x), int(st["pos"].z)]
	var rep := int(board_rep.get(board, 0))
	var kinds := ["delivery", "delivery", "fight", "carry"]
	if world.ride and not world.ride.on_water:
		kinds = ["fare", "fare", "delivery"]
	var kind: String = kinds[_rng.randi() % kinds.size()]
	var picks := _job_stops(st["pos"], 3)
	var dest: String = picks[0]
	var dname := String(world.map.landmarks[dest]["name"])
	var pay := 0
	var steps: Array = []
	var fragile := false
	var careful := false
	var late := false
	match kind:
		"delivery":
			var drops := 1 + _rng.randi() % 3
			fragile = _rng.randf() < 0.4
			var route: Array = picks.slice(0, drops)
			var dist := 0.0
			var prev: Vector3 = st["pos"]
			for d: String in route:
				var q := Terrain3D.w(world.map.landmarks[d]["pos"])
				dist += prev.distance_to(q)
				prev = q
			var secs := int(dist / 7.5) + 40 * drops
			pay = int(dist * 4.0 / 100.0) * 100 + 1200 * drops + (1500 if fragile else 0)
			var names := ", ".join(route.map(func(d: String) -> String: return String(world.map.landmarks[d]["name"])))
			steps.append({ "do": "say", "lines": [{ "who": "story", "text": "\"%s: %s. %d seconds for all of it.%s\"" % ["One parcel" if drops == 1 else "%d drops" % drops, names, secs, " Handle with care: na glass!" if fragile else ""] }] })
			for i in route.size():
				steps.append({ "do": "goto", "at": "landmark:" + String(route[i]), "radius": 8, "time": secs if i == 0 else maxi(30, secs / 2), "text": "%s parcel %d of %d to %s." % ["Fragile:" if fragile else "Deliver", i + 1, route.size(), String(world.map.landmarks[route[i]]["name"])] })
		"fare":
			var req: String = ["careful", "late", "stop", "plain"][_rng.randi() % 4]
			pay = 1400 + _rng.randi_range(0, 8) * 100
			var line := "\"%s! How much? Oya, carry me.\"" % dname
			match req:
				"careful":
					careful = true
					line = "\"%s. Drive gently o, I just do surgery. Any jam-jam, I no go pay full.\"" % dname
				"late":
					late = true
					pay += 1000
					line = "\"%s! Fast fast, I don late for interview! Get me there and I go add ₦1,000.\"" % dname
				"stop":
					pay += 600
					line = "\"Stop for %s first, I wan collect something. Then %s.\"" % [String(world.map.landmarks[picks[1]]["name"]), dname]
			steps.append({ "do": "say", "lines": [{ "who": "passenger", "text": line }] })
			if req == "stop":
				steps.append({ "do": "goto", "at": "landmark:" + String(picks[1]), "radius": 8, "on": "vehicle", "time": 200, "text": "The passenger's stop: %s." % String(world.map.landmarks[picks[1]]["name"]) })
			var d0: float = Terrain3D.w(world.map.landmarks[dest]["pos"]).distance_to(world.focus())
			steps.append({ "do": "goto", "at": "landmark:" + dest, "radius": 8, "on": "vehicle", "time": int(d0 / 9.0) + 30 if late else 240, "text": "Carry the passenger to %s.%s" % [dname, " Hurry!" if late else (" Gently!" if careful else "")] })
		"fight":
			pay = 3000 + rep * 300
			steps = [
				{ "do": "say", "lines": [{ "who": "agbero", "text": "\"Some boys dey disturb our traders. Na you be Sabi? Show them.\"" }] },
				{ "do": "fight", "text": "Run the troublemakers out of the market.", "enemies": [{ "id": "s1", "who": "agbero", "hp": 3 }, { "id": "s2", "who": "agbero", "hp": 3 }, { "id": "s3", "who": "agbero", "hp": 4, "type": "brute" if rep > 1 else "thug" }] },
			]
		"carry":
			pay = 2000
			steps = [
				{ "do": "spawn", "id": "mw", "who": "passenger", "at": "player", "offset": [1.5, 1.0], "face": "player" },
				{ "do": "say", "lines": [{ "who": "passenger", "text": "\"My son, help me carry this load to %s. God go bless you.\"" % dname }] },
				{ "do": "escort", "id": "mw", "at": "landmark:" + dest, "radius": 8, "text": "Walk the market woman to %s." % dname },
			]
	pay = int(pay * (1.0 + mini(rep, 6) * 0.05))
	if postgame == "japa":
		pay = int(pay * 1.5)
	_side_running = true
	_set_prompt("", Callable())
	var hp0: float = world.ride.health if world.ride else 100.0
	var ok: bool = await world.missions.run_side(steps, "Side job" + (" · board reputation %d" % rep if rep > 0 else ""))
	_side_running = false
	var hit: float = hp0 - (world.ride.health if world.ride else hp0)
	if ok and fragile and hit > 8.0:
		pay = int(pay * 0.3)
		world.notify("You hear glass breaking in the parcel. They pay you only ₦%s." % _n(pay))
	elif ok and careful and hit > 5.0:
		pay = int(pay * 0.5)
		world.notify("\"Na so you dey drive? My stitches!\" Half fare.")
	if ok:
		Life.earn(pay, "Side job: %s (3D)" % kind)
		Sound.sfx("cash")
		Story.add_respect(1)
		_streak += 1
		board_rep[board] = rep + 1
		world.notify("Side job done: ₦%s. (Respect +1)" % _n(pay))
		if _streak % 3 == 0:
			var bonus := 1500 * (_streak / 3)
			Life.earn(bonus, "Side job streak bonus (3D)")
			world.notify("%d jobs in a row: your name is ringing in the market. Bonus ₦%s." % [_streak, _n(bonus)])
	else:
		_streak = 0
		Story.add_respect(-1)
		board_rep[board] = maxi(0, rep - 1)
		world.notify("Side job failed. Word gets round. (Respect -1)")


## Landmarks that make a good route from a job board: not too near, not across the whole city.
func _job_stops(from: Vector3, n: int) -> Array:
	var lms: Array = world.map.landmarks.keys().filter(func(k: String) -> bool:
		var d := Terrain3D.w(world.map.landmarks[k]["pos"]).distance_to(from)
		return d > 200.0 and d < 750.0)
	if lms.size() < n:
		lms = world.map.landmarks.keys()
	lms.shuffle()
	return lms.slice(0, n)


# ---------- Radio Gbedu ----------

func _radio(delta: float) -> void:
	var ride: Vehicle3D = world.ride
	if ride == null or not radio_on:
		world.hud.radio("")
		if Sound._music_name == "highlife" and not world.in_menu:
			Sound.music("")
		return
	if Sound._music_name == "":
		Sound.music("highlife")
	_radio_t -= delta
	if _radio_t > 0.0:
		return
	_radio_t = 9.0
	_radio_i += 1
	var line := ""
	if _radio_i % 3 == 0:
		line = RADIO_ADS[_rng.randi() % RADIO_ADS.size()]
	elif _radio_i % 3 == 1:
		line = _news()
	else:
		line = RADIO_DJ[_rng.randi() % RADIO_DJ.size()]
	world.hud.radio("📻 " + line)


## The news follows the story.
func _news() -> String:
	var d: Dictionary = Story.done
	if d.has("m25"):
		return "NEWS: Senator Coker-Bankole arrested at his Banana Island gala. CP Ladipo in custody, live on air."
	if d.has("m22"):
		return "NEWS: Oshodi park is quiet today. Union boys say \"we know who our enemy is now\"."
	if d.has("m18"):
		return "NEWS: Gunmen in police uniform attack a Festac home. One elderly woman confirmed dead."
	if d.has("m14"):
		return "NEWS: Election results: the Senator leads. Opposition cries foul over snatched ballot boxes."
	if d.has("m12"):
		return "NEWS: Alhaji Rasaki \"Kongi\" Adio, Oshodi park chairman, shot dead on Third Mainland Bridge."
	if d.has("m06"):
		return "NEWS: Police say a danfo driver's burned bus carried \"evidence of human trafficking\"."
	return "NEWS: The Senator promises \"Eko for Everybody\" at a rally in Surulere."


# ---------- post-game ----------

func start_postgame(ending: String) -> void:
	postgame = ending
	var line := ""
	match ending:
		"staff": line = "Post-game: Oba Ìta. Oshodi is yours. Every park pays its dues to you at midnight."
		"judgment": line = "Post-game: Chairman Balogun. Oshodi elected you fairly. Union dues come in every day."
		"judgment_bitter": line = "Post-game: Obinna walks free on bail. Lagos goes on. So do you."
		"japa": line = "Post-game: a neutral driver again. Every gang has work for you; side jobs pay half as much again."
	world.notify(line)
	world.set_objective(line, null)
	world._save_game()


func _postgame_income() -> void:
	var amt := { "staff": 20000, "judgment": 8000 }.get(postgame, 0) as int
	if amt > 0:
		Life.earn(amt, "Oshodi dues (3D)")
		world.notify("The parks' dues came in: ₦%s." % _n(amt))


# ---------- save ----------

func to_dict() -> Dictionary:
	return { "owned": owned, "today": today, "debt": debt, "buffs": buffs, "postgame": postgame, "radio": radio_on, "boards": board_rep, "found": found }


func from_dict(d: Dictionary) -> void:
	owned = d.get("owned", [])
	today = int(d.get("today", 0))
	debt = int(d.get("debt", 0))
	buffs = d.get("buffs", {})
	postgame = String(d.get("postgame", ""))
	radio_on = bool(d.get("radio", true))
	board_rep = d.get("boards", {})
	found = d.get("found", {})
	# The Ìrókò charm (Act II) stays for good once Baba Fakunle has given it.
	if Story.items.has("iroko"):
		buffs["iroko"] = 1e9


func _n(v: int) -> String:
	return Life.fmt_naira(v)
