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
	await _test_story()
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


## Story engine (M3): data integrity, a full Prologue + Act 1 run on a fake host, switching,
## abilities and saving. Story scripts use autoloads, so they are loaded at runtime.
func _test_story() -> void:
	var story: Node = root.get_node("Story")
	var life: Node = root.get_node("Life")
	var m := MapData.shared()
	check(story.missions.size() >= 22, "the whole story is scripted: Prologue, Acts 1-3, epilogue (%d missions)" % story.missions.size())
	# Data integrity: every reference resolves.
	var bad: Array = []
	var games := ["jollof", "spray", "quick", "counting", "standoff", "pos", "interview", "dresscode", "board", "dodge", "gist", "debate", "cue", "spray_dance"]
	for id in story.order:
		var mission: Dictionary = story.missions[id]
		var refs: Array = []
		if mission.has("start"):
			refs.append(mission["start"])
		for s in mission["steps"]:
			for w in s.get("watchers", []):
				refs.append(w["at"])
				if not story.cast.has(w["who"]):
					bad.append("%s: unknown watcher %s" % [id, w["who"]])
			if s.get("do") in ["interior"] and not ["owambe", "compound", "stadium"].has(s["room"]):
				bad.append("%s: unknown room %s" % [id, s["room"]])
			if s.get("do") == "npc" and not story.cast.has(s.get("who", s["id"])):
				bad.append("%s: unknown npc %s" % [id, s.get("who", s["id"])])
			for pt in s.get("points", []):
				if pt.has("who") and not story.cast.has(pt["who"]):
					bad.append("%s: unknown stop npc %s" % [id, pt["who"]])
		for s in mission["steps"]:
			for k in ["at", "to"]:
				if s.has(k) and s[k] is String:
					refs.append(s[k])
			if s.get("do") == "say" and s["lines"] is String and story.line_list(s["lines"]).is_empty():
				bad.append("%s: missing dialogue %s" % [id, s["lines"]])
			if s.get("do") == "minigame" and not s["game"] in games:
				bad.append("%s: unknown mini-game %s" % [id, s["game"]])
			if s.get("do") == "chat" and not story.chats.get("scripted", {}).has(s["chat"]):
				bad.append("%s: missing chat %s" % [id, s["chat"]])
			if s.get("do") == "minigame" and s.get("params", {}).get("lines", null) is String and story.line_list(s["params"]["lines"]).is_empty():
				bad.append("%s: missing standoff lines" % id)
			if s.get("do") == "panels":
				for pn in s["panels"]:
					if Art.tex(pn["img"]) == null:
						bad.append("%s: missing panel art %s" % [id, pn["img"]])
			for pt in s.get("points", []):
				refs.append(pt["at"])
				if pt.has("say") and story.line_list(pt["say"]).is_empty():
					bad.append("%s: missing dialogue %s" % [id, pt["say"]])
		for r in refs:
			var rs := String(r)
			if rs.begins_with("landmark:") and not m.landmarks.has(rs.trim_prefix("landmark:")):
				bad.append("%s: unknown landmark %s" % [id, rs])
			if rs.begins_with("node:") and not m.road_nodes.has(rs.trim_prefix("node:")):
				bad.append("%s: unknown road node %s" % [id, rs])
	for key in story.dialogue:
		for line in story.dialogue[key]:
			var w := String(line.get("who", ""))
			if not story.cast.has(w):
				bad.append("dialogue %s: unknown speaker %s" % [key, w])
	for w in story.cast:
		var c: Dictionary = story.cast[w]
		if c.has("portrait") and Art.tex(c["portrait"]) == null:
			bad.append("cast %s: missing portrait" % w)
	check(bad.is_empty(), "story data references resolve: %s" % str(bad.slice(0, 5)))
	for h in story.HEROES:
		check(Art.tex(story.HERO_SHEET[h]) != null and not Art.sheet_info(story.HERO_SHEET[h]).is_empty(), "%s has a walk sheet" % h)
		check(m.landmarks.has(story.HERO_HOME[h]), "%s has a home landmark" % h)

	# Full run on the fake host.
	story.reset()
	life.flags = {}
	var host: Node = load("res://tests/fake_story_host.gd").new()
	root.add_child(host)
	var runner: Node = load("res://story/mission_runner.gd").new()
	root.add_child(runner)
	host.runner = runner
	runner.setup(host, m)
	host.pick = 2 # "Count it first" in 1.5
	runner.start("P1")
	var frames := 0
	while not story.is_done("P4") and frames < 4000:
		await process_frame
		frames += 1
	check(story.is_done("P1") and story.is_done("P2") and story.is_done("P3") and story.is_done("P4"), "the Prologue chains P1 → P4 by itself")
	check(story.switching, "hero switching unlocks after the Prologue")
	check(host.minigames.has("jollof") and host.minigames.has("spray") and host.minigames.has("quick"), "Prologue mini-games run: %s" % str(host.minigames))
	check(life.hero == "tunde", "Tunde is in control after the Prologue (got %s)" % life.hero)
	check(not story.available().has("1.4") and story.available().has("1.1"), "1.4 waits for 1.1")
	for id in ["1.1", "1.2", "1.3", "1.4", "1.5"]:
		runner.start(id)
		frames = 0
		while not story.is_done(id) and frames < 3000:
			await process_frame
			frames += 1
		check(story.is_done(id), "mission %s completes" % id)
	check(host.fails == 0, "no step failed on the happy path (%d)" % host.fails)
	check(story.flag("bag_choice") == "count" and story.flag("act1_done"), "the bag choice is remembered (%s)" % str(story.flag("bag_choice")))
	check(host.minigames.has("counting") and host.minigames.has("pos") and host.minigames.has("standoff"), "Act 1 mini-games run")
	check(story.tier("whisperer") >= 1 and story.tier("ajo") >= 1 and story.tier("golive") >= 1, "Act 1 unlocks Whisperer, Ajo Network and Go Live")
	check(story.story_money > 0 and life.has_item("the-bag"), "story money and the bag are awarded")
	check(story.family_rel() > 50, "Family Meeting raises trust (%d)" % story.family_rel())
	# Act 2 opens in any order: Block B needs two of Block A.
	check(story.available().has("2.1") and story.available().has("2.2") and story.available().has("2.3"), "Act 2 Block A is open after Act 1")
	check(not story.available().has("2.4"), "Block B waits for two Block A missions")
	host.pick = 0
	for id in ["2.1", "2.3"]:
		runner.start(id)
		frames = 0
		while not story.is_done(id) and frames < 3000:
			await process_frame
			frames += 1
		check(story.is_done(id), "mission %s completes" % id)
	check(story.available().has("2.4") and story.available().has("2.5") and story.available().has("2.6"), "two of Block A open Block B")
	check(story.tier("stare") >= 2 and story.flag("canteen_socket"), "Generator Wars: group Stare and the canteen socket")
	for id in ["2.2", "2.4", "2.5", "2.6", "2.7", "2.8", "3.1", "3.2", "3.3", "3.4"]:
		runner.start(id)
		frames = 0
		while not story.is_done(id) and frames < 4000:
			await process_frame
			frames += 1
		check(story.is_done(id), "mission %s completes" % id)
	frames = 0
	while not story.is_done("3.5") and frames < 3000:
		await process_frame
		frames += 1
	check(story.is_done("3.5") and story.flag("story_complete"), "the epilogue follows the finale and the story completes")
	check(story.flag("ending") in ["A", "B", "C", "D"], "an ending was chosen (%s)" % str(story.flag("ending")))
	check(story.flag("japa_possible") and story.flag("japa_chosen") and story.flag("ending") == "C", "passing the interview and choosing to go gives the Japa ending")
	check(story.diary_pages >= 5 and story.evidence >= 1, "diary pages and evidence were collected (%d, %d)" % [story.diary_pages, story.evidence])
	check(story.story_money == 0 and life.money > 0, "story money joins the wallet at the end")
	check(host.minigames.has("interview") and host.minigames.has("board") and host.minigames.has("cue") and host.minigames.has("debate"), "Act 2/3 mini-games run")
	# Ending rules.
	life.flags = { "old_notes": "kept", "japa_chosen": true }
	check(story.compute_ending() == "B", "keeping the old notes is the Hustle ending, whatever else happened")
	life.flags = { "old_notes": "handed", "japa_chosen": true }
	check(story.compute_ending() == "C", "choosing to go is the Japa ending")
	life.flags = { "old_notes": "handed", "stitch_key": true }
	story.diary_pages = 10
	check(story.compute_ending() == "D", "ten diary pages and the stitch key give the Secret ending")
	story.diary_pages = 9
	check(story.compute_ending() == "A", "otherwise the Honest ending")
	life.flags = { "old_notes": "handed", "tried_honest": true }
	life.relationships = { "tunde-ngozi": 70, "tunde-kc": 65, "ngozi-kc": 80 }
	check(story.honest_ending_full(), "honest from the start + handed over + trust 60+ = the full Honest ending")
	story.blocs = { "traders": 60, "drivers": 60, "students": 60, "church": 60, "okada": 60, "youth": 60 }
	check(story.teacher_support() == 60, "Teacher's support is the bloc average")
	story.apply_effects({ "blocs": { "all": -100 } })
	check(story.teacher_support() == 0, "blocs clamp at 0")
	# A failed mini-game offers a retry from the last checkpoint, then the mission completes.
	host.fails = 0
	host.fail_games = 1
	story.done.erase("P2")
	var jollof_before: int = host.minigames.count("jollof")
	runner.start("P2")
	frames = 0
	while not story.is_done("P2") and frames < 3000:
		await process_frame
		frames += 1
	check(host.fails == 1 and story.is_done("P2"), "failing the jollof rush retries and then completes P2")
	check(host.minigames.count("jollof") == jollof_before + 2, "the retry replays the mini-game from its checkpoint")
	check(story.is_done("P3"), "a replayed mission does not re-run the missions after it")
	# Saving.
	var snap: Dictionary = story.to_dict()
	story.reset()
	check(not story.is_done("1.5"), "reset clears progress")
	story.from_dict(snap)
	check(story.is_done("1.4") and story.tier("ajo") >= 1, "story progress round-trips through the save")
	runner.queue_free()
	host.queue_free()

	# Switching keeps each hero's own needs and position.
	life.hero = "tunde"
	life.needs["hunger"] = 33.0
	var res: Dictionary = story.swap_hero("ngozi", Vector2(500, 600))
	check(life.hero == "ngozi" and life.home == "aunty-boss-kitchen", "switching to Aunty Boss moves home to her kitchen")
	life.needs["hunger"] = 90.0
	res = story.swap_hero("tunde", Vector2(10, 10))
	check(res["pos"] == Vector2(500, 600), "Tunde comes back where he was left")
	check(life.needs["hunger"] < 40.0, "Tunde keeps his own hunger (%.0f)" % life.needs["hunger"])

	# Abilities.
	var ab: Node = load("res://story/abilities.gd").new()
	root.add_child(ab)
	life.hero = "tunde"
	life.stats["bp"] = 90.0
	for i in 10:
		ab.tick(1.0, { "mode": "driving", "stuck": true })
	check(ab.in_wahala(), "BP 100 triggers Wahala Mode")
	for i in 8:
		ab.tick(1.0, { "mode": "driving", "stuck": false })
	check(not ab.in_wahala() and life.stats["bp"] < 100.0, "Wahala Mode ends and BP drops")
	life.hero = "kc"
	life.stats["battery"] = 10.0
	ab.use("film")
	check(ab.filming, "KC can film")
	for i in 60:
		ab.tick(1.0, {})
	check(life.stats["battery"] <= 0.0 and not ab.filming, "filming drains the battery and stops at 0%")
	check(not ab.use("film"), "a dead phone can't film")
	life.hero = "ngozi"
	life.stats["aura"] = 100.0
	check(is_equal_approx(ab.stare_seconds(), 6.0), "full Aura doubles The Stare")
	check(ab.tier("stare") >= 1 and ab.tier("conductor") >= 1, "Prologue abilities are available from the start")
	ab.queue_free()
	life.hero = "tunde"
	story.reset()
	life.flags = {}
