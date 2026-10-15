class_name StreetHost
extends Node
## The street systems (M9–M11), wired into the game in one place. main.gd creates this after
## the world is built and calls tick() every frame. Each module keeps to its own job:
##   care (fuel, damage, repairs, crash feedback), checkpoints, heat (Area heat + Task Force),
##   passengers, weather (rain, floods), radio, reactions (pedestrians), life (hustles, owambe,
##   daily events, fishing, fleet, home, style) and online (races, crews, co-op, boxing, trading,
##   photos and the Lagos Gist feed).
## Story missions come first: anything that could derail one (checkpoints, the Task Force,
## floods, running dry) waits while a mission, cut-scene, mini-game, interior or chase is on.

var main: Node2D
var fx: StreetFx
var care: VehicleCare
var checkpoints: Checkpoints
var heat: AreaHeat
var passengers: Passengers
var weather: Weather
var radio: Radio
var reactions: Reactions
var hustles: Hustles
var life: StreetLife
var online: StreetOnline
var fights: FightStage
var points: Array = [] # service points: {pos, kind, label, ...}
var _hud: Control
var _fuel_bar: ProgressBar
var _bus_bar: ProgressBar
var _heat_label: Label
var _ticker: Label
var _radio_btn: Button
var _ticker_t := 0.0
var _bridge_day := -1
var demo_pick := "" # demo screenshots: which option the card picks


func setup(m: Node2D) -> void:
	main = m
	fx = StreetFx.new()
	main.add_child(fx)
	care = VehicleCare.new()
	checkpoints = Checkpoints.new()
	heat = AreaHeat.new()
	passengers = Passengers.new()
	weather = Weather.new()
	radio = Radio.new()
	reactions = Reactions.new()
	hustles = Hustles.new()
	life = StreetLife.new()
	online = StreetOnline.new()
	fights = FightStage.new()
	for mod: Node in [care, checkpoints, heat, passengers, weather, radio, reactions, hustles, life, online, fights]:
		add_child(mod)
		mod.setup(self)
	points = care.build_points(main.map) + life.build_points(main.map) + hustles.build_points(main.map)
	_build_hud()
	Street.unlocked.connect(func(_id: String, title: String) -> void:
		Sound.sfx("success")
		main.hud.toast("Award: %s" % title))
	main.jobs.job_changed.connect(passengers.on_job_changed)


## True while the story needs the player's full attention.
func story_busy() -> bool:
	var s: StoryHost = main.story
	return s.mission_running() or s.paused_by_story() or s.interior.active or s.chase.active or s.auto


func tick(dt: float) -> void:
	care.tick(dt)
	checkpoints.tick(dt)
	heat.tick(dt)
	passengers.tick(dt)
	weather.tick(dt)
	radio.tick(dt)
	reactions.tick(dt)
	hustles.tick(dt)
	life.tick(dt)
	online.tick(dt)
	_tick_awards()
	_update_hud(dt)


var _hero := ""


func _tick_awards() -> void:
	if Life.hero != _hero:
		_hero = Life.hero
		life.apply_style() # the outfit shows on whoever you're playing
	# "Survived Third Mainland at 5pm": on the bridge during the evening rush.
	if main.mode == "driving" and Clock.hour() == 17 and _bridge_day != Clock.day():
		if main.map.surface_at(main.danfo.position) == MapData.S.BRIDGE:
			_bridge_day = Clock.day()
			Street.count("bridge_rush")


func pick(a: Array) -> String:
	return String(a[randi() % a.size()]) if not a.is_empty() else ""


# ---------- prompts (the action button) ----------

## The nearest street service to `focus`, or {}.
func prompt(focus: Vector2) -> Dictionary:
	var reach := 170.0 if main.mode == "driving" else 95.0
	var best := {}
	var bd := reach
	for p: Dictionary in points:
		var d: float = focus.distance_to(p["pos"])
		if d < bd:
			var label := _label_for(p)
			if label != "":
				bd = d
				best = p.duplicate()
				best["label"] = label
	return best


func _label_for(p: Dictionary) -> String:
	match p["kind"]:
		"fuel", "jerrycan", "mechanic", "vulcanizer":
			return care.prompt_for(p) if main.mode == "driving" or p["kind"] in ["fuel", "mechanic"] else ""
		_:
			var l := life.prompt_for(p)
			return l if l != "" else hustles.prompt_for(p)


func act(p: Dictionary) -> void:
	match p["kind"]:
		"fuel", "jerrycan", "mechanic", "vulcanizer":
			care.use(p)
		_:
			if not life.use(p):
				hustles.use(p)


# ---------- a choice card ----------

## Shows a card with buttons; returns the chosen key. Freezes driving while it's up.
## options: [[key, label, enabled?], ...]. `seconds` > 0 picks `timeout_key` when time runs out.
func ask(title: String, body: String, options: Array, seconds := 0.0, timeout_key := "") -> String:
	var hud: CanvasLayer = main.hud
	var card: VBoxContainer = hud._card(hud._root, title, body)
	var dlg: Control = hud._dialog_root(card)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 8)
	card.add_child(row)
	var picked := [""]
	for o: Array in options:
		var key: String = o[0]
		var b: Button = hud._button(o[1], func() -> void: picked[0] = key)
		b.custom_minimum_size = Vector2(180, 56)
		b.disabled = o.size() > 2 and not o[2]
		row.add_child(b)
	main.story._busy += 1
	var t := 0.0
	while picked[0] == "":
		await get_tree().process_frame
		t += get_process_delta_time()
		if seconds > 0.0 and t >= seconds:
			picked[0] = timeout_key
		if main.story.auto or (main.demo and t > 1.2):
			picked[0] = demo_pick if demo_pick != "" else options[0][0]
	main.story._busy -= 1
	dlg.queue_free()
	return picked[0]


# ---------- impound ----------

func impound(reason: String) -> void:
	if Street.impounded:
		return
	if main.mode == "driving":
		main.danfo.speed = 0.0
		main._enter_exit()
	var yard: Vector2 = main.map.landmarks.get(Street.db["impound"]["yard"], {}).get("pos", main.danfo.position)
	main.danfo.position = yard + Vector2(90, 40)
	main.danfo.speed = 0.0
	Street.impounded = true
	Street.count("impounds")
	if not main.jobs.active.is_empty():
		main.jobs.cancel()
	Street.post_gist("impound", "%s's danfo was towed to the impound yard. %s" % [Street._me(), reason])
	main.hud.toast("Your bus has been impounded (%s). Pay ₦%s at the %s." % [reason, Life.fmt_naira(int(Street.db["impound"]["fee"])), Street.db["impound"]["name"]])


# ---------- HUD ----------

func _build_hud() -> void:
	var root: Control = main.hud._root
	_hud = VBoxContainer.new()
	_hud.position = Vector2(14, 392)
	_hud.add_theme_constant_override("separation", 3)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hud)
	_fuel_bar = _bar("Fuel", Color("#e0a91c"))
	_bus_bar = _bar("Bus", Color("#2f8a52"))
	_heat_label = _small_label("")
	_heat_label.add_theme_color_override("font_color", Color("#ff7a5c"))
	_hud.add_child(_heat_label)
	_ticker = _small_label("")
	_ticker.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_ticker.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ticker.offset_bottom = -34
	_ticker.offset_top = -60
	_ticker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ticker.add_theme_font_size_override("font_size", 15)
	root.add_child(_ticker)
	_radio_btn = main.hud._button("Radio", func() -> void: radio.next_station())
	_radio_btn.custom_minimum_size = Vector2(150, 44)
	_radio_btn.add_theme_font_size_override("font_size", 14)
	_radio_btn.position = Vector2(14, 470)
	root.add_child(_radio_btn)


func _bar(label: String, col: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	var l := _small_label(label)
	l.custom_minimum_size = Vector2(40, 0)
	row.add_child(l)
	var pb := ProgressBar.new()
	pb.max_value = 100
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(124, 9)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.11, 0.09, 0.07, 0.7)
	bg.set_corner_radius_all(4)
	pb.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(4)
	pb.add_theme_stylebox_override("fill", fill)
	row.add_child(pb)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(row)
	return pb


func _small_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color("#f1e6c8"))
	l.add_theme_color_override("font_outline_color", Color("#1d1611"))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func ticker(text: String, seconds := 7.0) -> void:
	_ticker.text = text
	_ticker_t = seconds


func _update_hud(dt: float) -> void:
	var driving: bool = main.mode == "driving" and not main.story.interior.active
	_fuel_bar.get_parent().visible = driving or Street.fuel < 25.0
	_bus_bar.get_parent().visible = driving or Street.damage > 30.0
	_fuel_bar.value = Street.fuel
	_bus_bar.value = 100.0 - Street.damage
	var st := Street.stars()
	_heat_label.visible = Street.heat >= 0.5
	_heat_label.text = "Area heat " + "★".repeat(maxi(st, 1 if Street.heat >= 0.5 else 0)) + "☆".repeat(5 - maxi(st, 1 if Street.heat >= 0.5 else 0))
	_radio_btn.visible = driving
	_radio_btn.text = "Radio: %s" % radio.station_short()
	_ticker_t -= dt
	_ticker.visible = _ticker_t > 0.0 and not main.story.paused_by_story()
