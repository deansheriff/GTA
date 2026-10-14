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
	check(m.landmarks.size() == 10, "all story landmarks placed")
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
	_test_nav(m)


func _test_nav(m: MapData) -> void:
	var t0 := Time.get_ticks_msec()
	var nav := Nav.new()
	nav.setup(m)
	print("nav: built in %d ms" % (Time.get_ticks_msec() - t0))
	var from: Vector2 = m.landmarks["aunty-boss-kitchen"]["pos"]
	var to: Vector2 = m.landmarks["oshodi-market"]["pos"]
	var walk := nav.walk_path(from, to)
	check(walk.size() >= 2, "can walk from Aunty Boss Kitchen to Oshodi Market")
	var ok := true
	for p in walk:
		if m.is_blocked(p) and p.distance_to(to) > 64.0:
			ok = false
	check(ok, "walking path avoids buildings and water")
	var drive := nav.drive_path(m.landmarks["kc-room"]["pos"], m.landmarks["lekki-event-centre"]["pos"])
	check(drive.size() >= 2, "GPS route from Yaba to the Lekki event centre exists")
	var crosses_bridge := false
	for p in drive:
		if m.surface_at(p) == MapData.S.BRIDGE:
			crosses_bridge = true
	check(crosses_bridge, "the Yaba to Lekki route crosses the lagoon by bridge")


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
	# A full delivery job.
	var m := MapData.shared()
	var jr: Node = load("res://world/job_runner.gd").new() # loaded at runtime: uses autoloads
	root.add_child(jr)
	jr.setup(m)
	check(jr.offers.size() >= 4, "the phone lists today's gigs (%d)" % jr.offers.size())
	var del: Array = jr.offers.filter(func(o: Dictionary) -> bool: return o["type"] == "delivery")
	check(not del.is_empty(), "there is a delivery gig today")
	if not del.is_empty():
		var before: int = life.money
		jr.accept(del[0])
		jr.tick(0.1, jr.start_pos(jr.active), "walking", false)
		check(jr.active.get("stage", "") == "deliver", "arriving at the pickup starts the delivery")
		jr.tick(0.1, jr.end_pos(jr.active), "walking", false)
		check(jr.active.is_empty() and life.money > before, "delivering pays (₦%d)" % (life.money - before))
	jr.queue_free()
