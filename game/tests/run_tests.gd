extends SceneTree
## Headless unit tests:
##   Godot --headless --path game --script res://tests/run_tests.gd

var failures := 0
var passes := 0


func check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
	else:
		failures += 1
		printerr("FAIL: ", label)


func _initialize() -> void:
	_test_device_profile()
	_test_layout()
	_test_map()
	await process_frame # autoloads (Clock, Life, SaveGame) are ready after the first frame
	_test_life()
	_test_campaign()
	_test_street()
	_test_ui()
	_test_world3d()
	print("tests: %d passed, %d failed" % [passes, failures])
	quit(1 if failures > 0 else 0)


func _test_device_profile() -> void:
	var s := DeviceProfile.suggest({ "ram_gb": 2.0, "cores": 4, "is_mobile": true })
	check(s["preset"] == "low" and s["data_saver"], "2 GB phone suggests Low + data saver")
	s = DeviceProfile.suggest({ "ram_gb": 8.0, "cores": 8, "is_mobile": true })
	check(s["preset"] == "medium", "phones never default to High")
	s = DeviceProfile.suggest({ "ram_gb": 16.0, "cores": 12, "is_mobile": false })
	check(s["preset"] == "high", "strong desktop suggests High")
	s = DeviceProfile.suggest({ "ram_gb": 4.0, "gpu": "Mali-400 MP", "is_mobile": true })
	check(s["preset"] == "low", "old Mali GPU drops to Low")
	s = DeviceProfile.suggest({ "ram_gb": 8.0, "cores": 8, "bench_ms": 40.0 })
	check(s["preset"] == "low", "slow benchmark drops to Low")
	var hi := DeviceProfile.apply_data_saver(DeviceProfile.from_preset("high"), true)
	check(hi["texture_tier"] == "lo" and hi["still_cutscenes"] and hi["fps_cap"] == 60, "data saver keeps the fps cap")


func _test_layout() -> void:
	var w := Layout.build_yaba()
	check(Layout.surface_at(Vector2(600, (Layout.MAIN_Y0 + Layout.MAIN_Y1) / 2.0)) == "road", "main road is road")
	check(Layout.surface_at(Vector2(700, 600)) == "ground", "town ground north of the road")
	check(not w.is_blocked(w.player_start), "player starts on walkable ground")
	check(not w.is_blocked(w.danfo_start), "danfo starts on walkable ground")
	var blocked := 0
	for b in w.buildings:
		if w.is_blocked(b.footprint().get_center()):
			blocked += 1
	check(blocked == w.buildings.size(), "every building footprint is solid")
	# Island (D-007)
	check(Layout.surface_at(Layout.ISLAND_CENTER + Vector2(-300, 0)) != "sea", "island centre is land")
	check(Layout.surface_at(Vector2(10, 10)) == "sea", "world corner is sea")
	check(w.is_blocked(Vector2(20, 20)), "the sea blocks walking and driving")
	check(w.buildings.size() >= 8, "most town lots stay on the island (%d)" % w.buildings.size())
	var beach := 0
	for p in w.props:
		if Layout.surface_at(p.pos) == "beach":
			beach += 1
	check(beach >= 10, "beach has life on it (%d props)" % beach)


func _test_map() -> void:
	var t0 := Time.get_ticks_msec()
	var script: Script = load("res://world/map_data.gd")
	if script == null or not script.can_instantiate():
		check(false, "map_data.gd compiles")
		return
	var m := MapData.new()
	m.load_file("res://data/map/lagos.json")
	var ms := Time.get_ticks_msec() - t0
	print("map: %dx%d cells, %d buildings, %d props, %d landmarks, built in %d ms" % [m.cols, m.rows, m.buildings.size(), m.props.size(), m.landmarks.size(), ms])
	check(ms < 8000, "map builds in under 8 s on desktop (%d ms)" % ms)
	check(m.buildings.size() > 250, "a full city of buildings (%d)" % m.buildings.size())
	check(m.props.size() > 400, "streets are furnished (%d props)" % m.props.size())
	check(m.landmarks.size() == 19, "all story landmarks placed (%d)" % m.landmarks.size())
	# Street poles are solid only where the pole is, not across their whole 64 px cell (owner
	# report: the bus got stuck next to a pole and couldn't turn away).
	var pole: Variant = null
	for pr in m.props:
		if pr.kind == "pole" and not m.is_blocked(pr.pos + Vector2(40, 0)) and not m.is_blocked(pr.pos - Vector2(40, 0)):
			pole = pr
			break
	check(pole != null, "found a free-standing street pole")
	if pole:
		check(m.is_blocked(pole.pos), "a pole is solid")
		check(not m.is_blocked(pole.pos + Vector2(22, 0)), "a step away from a pole is free (no invisible cell wall)")
		var half := Vector2(132, 58) * 0.46
		var touching: Vector2 = pole.pos + Vector2(0, half.y + 4.0)
		var free_spot := false
		for i in 8:
			var h := i * TAU / 8.0
			if not m.body_blocked(touching + Vector2.from_angle(h) * 6.0, h, half) or not m.body_blocked(touching + Vector2(0, 30), h, half):
				free_spot = true
		check(free_spot, "a bus parked against a pole can still drive away")
	var placed := {}
	for b in m.buildings:
		if b.landmark != "":
			placed[b.landmark] = true
	var missing: Array = []
	for id in m.landmarks:
		if MapData.CATALOG.has(m.landmarks[id]["kind"]) and not placed.has(id):
			missing.append(id)
	check(missing.is_empty(), "every building landmark got its building: missing %s" % str(missing))
	for id in m.landmarks:
		var p: Vector2 = m.landmarks[id]["pos"]
		check(not m.is_blocked(p), "landmark %s is reachable on foot" % id)
	check(m.is_water(m.surface_at(Vector2(10, 10))), "map corner is sea")
	check(m.surface_at(m.road_nodes["tmb_mid"]) == MapData.S.BRIDGE, "Third Mainland Bridge crosses the lagoon")
	check(not m.is_blocked(m.road_nodes["tmb_mid"]), "the bridge is drivable")
	check(m.district_at(m.road_nodes["yaba_c"]).get("name", "") == "Yaba", "Yaba is where Yaba should be")
	check(m.district_at(m.road_nodes["lekki_c"]).get("name", "") == "Lekki", "Lekki is where Lekki should be")
	check(not m.is_blocked(m.player_start), "player start is walkable")
	check(m.is_roadlike(m.surface_at(m.danfo_start)), "the danfo starts on a road")
	var beach := 0
	for i in m.surface.size():
		if m.surface[i] == MapData.S.BEACH:
			beach += 1
	check(beach > 300, "coastline has beaches (%d cells)" % beach)
	# Every road node is connected to the network.
	var seen := { "obalende": true }
	var stack := ["obalende"]
	while not stack.is_empty():
		var n: String = stack.pop_back()
		for nb in m.road_graph.get(n, []):
			if not seen.has(nb):
				seen[nb] = true
				stack.append(nb)
	var main_nodes := ["yaba_c", "ikeja_c", "ketu_c", "lekki_e", "surulere_c", "oshodi_c", "mushin_c", "vi_c"]
	for n in main_nodes:
		check(seen.has(n), "%s connected to Obalende by road" % n)



func _test_life() -> void:
	var life: Node = root.get_node("Life")
	var clock: Node = root.get_node("Clock")
	clock.minutes = 12 * 60
	check(is_equal_approx(clock.darkness(), 0.0), "noon is daylight")
	clock.minutes = 23 * 60
	check(is_equal_approx(clock.darkness(), 1.0), "11pm is night")
	clock.minutes = 18 * 60 + 45
	check(clock.darkness() > 0.2 and clock.darkness() < 0.8, "dusk is in between")
	check(clock.weekday() == "Monday" or clock.day() != 1, "day 1 is a Monday")
	life.money = 5000
	life.needs["hunger"] = 20.0
	check(life.buy("amala"), "can buy amala with ₦5,000")
	check(life.money < 5000 and life.needs["hunger"] > 60.0, "buying food costs money and fills the belle")
	life.money = 10
	check(not life.buy("jollof"), "can't buy jollof with ₦10")
	check(life.money == 10, "a failed purchase costs nothing")
	check(life.xp_for(1) == 100, "level 2 needs 100 XP")
	life.skills_xp["driving"] = 0
	life.add_xp("driving", 150)
	check(life.level("driving") == 2, "150 XP is driving level 2")
	clock.minutes = 22 * 60
	life.needs["energy"] = 5.0
	var slept: int = life.sleep()
	check(life.needs["energy"] == 100.0 and clock.minutes % 1440 == 6 * 60 + 30, "sleeping until 06:30 restores energy (%d min)" % slept)
	var save: Node = root.get_node("SaveGame")
	life.money = 12345
	var snap: Dictionary = save.snapshot()
	life.money = 1
	save.apply(snap)
	check(life.money == 12345, "save snapshot round-trips the wallet")


## Street systems state (M9–M11): awards, reputation prices, the bus, save round-trip.
func _test_street() -> void:
	var st: Node = root.get_node("Street")
	st.reset()
	var got := []
	var cb := func(id: String, _t: String) -> void: got.append(id)
	st.unlocked.connect(cb)
	for i in 9:
		st.count("agbero_paid")
	check(not got.has("agbero-10"), "an award waits for its goal")
	st.count("agbero_paid")
	check(got.has("agbero-10"), "\"Paid the agbero 10 times\" unlocks on the tenth")
	st.count("agbero_paid")
	check(got.count("agbero-10") == 1, "an award unlocks once")
	st.unlocked.disconnect(cb)
	st.rep = 80.0
	var cheap: float = st.price_k()
	st.rep = -80.0
	var dear: float = st.price_k()
	check(cheap < 1.0 and dear > 1.0, "street rep changes prices (%.2f / %.2f)" % [cheap, dear])
	st.rep = 0.0
	st.fuel = 0.0
	check(st.bus_limit() < 100.0, "an empty tank sputters")
	st.fuel = 50.0
	st.damage = 90.0
	check(st.bus_limit() < 200.0, "a wrecked bus limps")
	st.damage = 10.0
	check(st.bus_limit() == INF, "a healthy bus has no limit")
	st.add_heat(9.0)
	check(st.stars() == 5, "Area heat caps at five stars")
	var saved: Dictionary = st.to_dict()
	st.reset()
	st.from_dict(saved)
	check(st.stars() == 5 and int(st.counters.get("agbero_paid", 0)) == 11, "street state survives a save")
	var list: Array = st.achievement_list()
	check(list.size() >= 25 and list.filter(func(a: Dictionary) -> bool: return a["done"]).size() >= 2, "the awards list reports progress")
	st.reset()


## Èkó Ò Ní Bàjẹ́ (D-021): the campaign data is whole (27 missions, prologue + 5 acts), every
## playable step is a known kind whose places and speakers exist, and story state saves.
func _test_campaign() -> void:
	var story: Node = root.get_node("Story")
	check(story.order.size() == 27 and story.order[0] == "p0" and story.order[26] == "m26", "the campaign lists the prologue and 26 missions")
	var known := ["env", "player", "place", "spawn", "despawn", "clear", "title", "say", "item", "still", "escape", "goto", "fares", "fight", "exit", "cam", "black", "sfx", "respect", "choice", "flag", "wait", "chase", "pursuit", "follow", "escort", "roger", "gun", "news", "wanted", "crowd", "setpiece", "pay"]
	var m := MapData.shared()
	var bad := []
	var playable := 0
	for id: String in story.order:
		var mis: Dictionary = story.mission(id)
		if not mis.has("title") or not mis.has("act"):
			bad.append(id + " has no title/act")
		var steps: Array = mis.get("steps", [])
		if not steps.is_empty():
			playable += 1
		for st: Dictionary in steps:
			if not String(st.get("do", "")) in known:
				bad.append("%s: unknown step %s" % [id, st.get("do", "")])
			var at: Variant = st.get("at", "")
			if at is String and String(at).begins_with("landmark:") and not m.landmarks.has(String(at).substr(9)):
				bad.append("%s: no landmark %s" % [id, at])
			if at is String and String(at).begins_with("node:") and not m.road_nodes.has(String(at).substr(5)):
				bad.append("%s: no road node %s" % [id, at])
			for line: Dictionary in st.get("lines", []):
				if not story.cast.has(String(line.get("who", ""))):
					bad.append("%s: unknown speaker %s" % [id, line.get("who", "")])
			for e: Dictionary in st.get("enemies", []):
				if not story.cast.has(String(e.get("who", ""))):
					bad.append("%s: unknown fighter %s" % [id, e.get("who", "")])
			if st.has("who") and not story.cast.has(String(st["who"])):
				bad.append("%s: unknown actor %s" % [id, st["who"]])
	check(bad.is_empty(), "campaign data is consistent %s" % [bad])
	check(playable >= 7, "the prologue and Act I's opening are playable (%d)" % playable)
	story.reset()
	story.complete("p0")
	story.choose("ballot", "swap")
	story.choose("final", "judgment")
	check(story.next_mission() == "m01" and story.ending() == "judgment", "next mission and the Judgment ending follow the choices")
	story.choose("ballot", "snatch")
	check(story.ending() == "judgment_bitter", "snatching the ballot boxes sours Judgment")
	var snap: Dictionary = story.to_dict()
	story.reset()
	story.from_dict(snap)
	check(story.done.has("p0") and story.choices["ballot"] == "snatch", "story progress survives a save")
	story.reset()


## 3D Lagos (D-020): every model the 3D tables name exists, people are rigged with the shared
## action pack, and the 3D scripts compile.
func _test_world3d() -> void:
	var M: GDScript = load("res://world3d/models3d.gd")
	var missing := []
	for art: String in M.BUILDINGS:
		for k: String in M.BUILDINGS[art]:
			if not ResourceLoader.exists("res://art3d/%s.glb" % k):
				missing.append(k)
	for k: String in M.LANDMARKS:
		if not ResourceLoader.exists("res://art3d/%s.glb" % M.LANDMARKS[k]):
			missing.append(M.LANDMARKS[k])
	for kind: String in M.PROPS:
		if not ResourceLoader.exists("res://art3d/%s.glb" % M.PROPS[kind][0]):
			missing.append(M.PROPS[kind][0])
	for kind: String in M.VEHICLES:
		if not ResourceLoader.exists("res://art3d/%s.glb" % M.VEHICLES[kind]["model"]):
			missing.append(M.VEHICLES[kind]["model"])
	for k: String in M.PEOPLE + ["tunde"]:
		for f in ["%s.glb", "%s_run.glb"]:
			if not ResourceLoader.exists("res://art3d/chars/" + f % k):
				missing.append(f % k)
	for k in ["horse", "helicopter", "pistol", "rock_large", "mountain", "tent", "gazebo", "barrel", "gas_tank", "speedboat", "yacht", "canopy", "ambulance"]:
		if not ResourceLoader.exists("res://art3d/free/%s.glb" % k):
			missing.append("free/" + k)
	check(missing.is_empty(), "every 3D model exists (missing: %s)" % [missing])
	var lib: RefCounted = M.new()
	var got: Array = lib.person("walker")
	var ap: AnimationPlayer = got[1]
	check(ap != null and ap.has_animation("run") and ap.has_animation("idle") and ap.has_animation("talk"), "3D people get run + the shared action pack")
	if got[0]:
		(got[0] as Node).free()
	for f in ["street3d", "terrain3d", "city3d", "vehicle3d", "person3d", "player3d", "danfo_run3d", "minimap3d", "lights3d", "checkpoint3d", "stage3d", "combat3d", "mission3d", "hud3d", "police3d"]:
		check((load("res://world3d/%s.gd" % f) as GDScript).can_instantiate(), "world3d/%s.gd compiles" % f)


## UI polish (M13): message kinds and the toast stack limit.
func _test_ui() -> void:
	var ts: Script = load("res://ui/toast_stack.gd")
	check(ts.guess_kind("Fares: ₦8,400 for the run") == "money", "fares read as money in")
	check(ts.guess_kind("Bought Suya for ₦1,200") == "spend", "purchases read as money out")
	check(ts.guess_kind("Award: Roger that") == "award", "awards get the award style")
	var stack: Control = ts.new()
	root.add_child(stack)
	for i in 5:
		stack.show_toast("Message %d" % i)
	check(stack.get_child_count() == 3 and stack.latest() == "Message 4", "at most three messages, newest on top")
	root.remove_child(stack)
	stack.free()
	ts.call("release_fonts")
