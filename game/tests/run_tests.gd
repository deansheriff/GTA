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
