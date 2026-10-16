extends Control
## The in-game phone: Map, Hustle (today's gigs), Bank (wallet + ledger), Me (needs, skills),
## Settings. Story apps (Family Meeting chat) plug in later via add_app().

signal open_map
signal open_settings
signal accept_job(offer: Dictionary)
signal cancel_job

const INK := Color("#1d1611")
const PAPER := Color("#f1e6c8")
const DANFO := Color("#e0a91c")

var jobs: JobRunner
const APP_ICON := { "Map": "map", "Hustle": "hustle", "Bank": "bank", "Me": "me", "Settings": "settings", "Story": "story", "Switch": "switch", "Keke": "keke", "Chat": "chat", "Gigs": "gigs", "Profile": "me", "Vote": "vote", "Win": "win", "Garage": "garage", "Fleet": "fleet", "Home": "home", "Style": "style", "Awards": "awards", "Gist": "gist", "Race": "race", "Crew": "crew", "Boxing": "boxing", "Market": "market", "Camera": "camera" }
var _screen: VBoxContainer
var _title: Label
var _apps := [] # [{name, builder: Callable}]
## Home screen (M13): wallpaper, a dock of the four everyday apps, and badges on apps with news.
const DOCK := ["Map", "Hustle", "Bank", "Gist"]
var badges := {} # app name -> count
var _dock: HBoxContainer


func setup(job_runner: JobRunner) -> void:
	jobs = job_runner
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.02, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed: visible = false)
	add_child(dim)
	var body := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#241c15")
	sb.border_color = INK
	sb.set_border_width_all(6)
	sb.set_corner_radius_all(28)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	body.add_theme_stylebox_override("panel", sb)
	body.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	body.custom_minimum_size = Vector2(380, 560)
	body.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	body.position = Vector2(-24, -280)
	add_child(body)
	# Wallpaper: the island from the air (the title bake), dimmed so text stays readable.
	var aerial: Texture2D = load("res://art/title/aerial.jpg") if ResourceLoader.exists("res://art/title/aerial.jpg") else null
	if aerial:
		var crop := AtlasTexture.new()
		crop.atlas = aerial
		crop.region = Rect2(aerial.get_width() * 0.42, aerial.get_height() * 0.38, aerial.get_width() * 0.26, aerial.get_height() * 0.5)
		var wall := TextureRect.new()
		wall.texture = crop
		wall.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		wall.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		wall.modulate = Color(0.42, 0.4, 0.38)
		wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(wall)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	body.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var back := Button.new()
	back.text = "‹"
	back.custom_minimum_size = Vector2(44, 40)
	back.pressed.connect(show_home)
	top.add_child(back)
	_title = Label.new()
	_title.add_theme_color_override("font_color", PAPER)
	_title.add_theme_font_size_override("font_size", 20)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(44, 40)
	close.pressed.connect(func() -> void: visible = false)
	top.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_screen = VBoxContainer.new()
	_screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screen.add_theme_constant_override("separation", 8)
	scroll.add_child(_screen)
	_dock = HBoxContainer.new()
	_dock.alignment = BoxContainer.ALIGNMENT_CENTER
	_dock.add_theme_constant_override("separation", 10)
	var dock_bg := PanelContainer.new()
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color(0.95, 0.9, 0.79, 0.18)
	dsb.set_corner_radius_all(18)
	dsb.content_margin_top = 6
	dsb.content_margin_bottom = 6
	dock_bg.add_theme_stylebox_override("panel", dsb)
	dock_bg.add_child(_dock)
	v.add_child(dock_bg)
	add_app("Map", func() -> void:
		visible = false
		open_map.emit())
	add_app("Hustle", _build_hustle)
	add_app("Bank", _build_bank)
	add_app("Me", _build_me)
	add_app("Settings", func() -> void:
		visible = false
		open_settings.emit())
	jobs.offers_changed.connect(func() -> void: if visible and _title.text == "Hustle": _build_hustle())
	Life.changed.connect(func() -> void: if visible and _title.text in ["Bank", "Me"]: _apps.filter(func(a: Dictionary) -> bool: return a["name"] == _title.text)[0]["builder"].call())


func add_app(app_name: String, builder: Callable) -> void:
	_apps.append({ "name": app_name, "builder": builder })


## A small red count on an app's icon (fleet report, new award, crew news…). 0 clears it.
func set_badge(app_name: String, n: int) -> void:
	if n <= 0:
		badges.erase(app_name)
	else:
		badges[app_name] = n
	if visible and _title.text.begins_with("Naija Street Life"):
		show_home()


func badge_total() -> int:
	var t := 0
	for k in badges:
		t += int(badges[k])
	return t


func open() -> void:
	visible = true
	Sound.sfx("tap")
	show_home()


func show_home() -> void:
	_clear("Naija Street Life · %s" % Clock.label())
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_screen.add_child(grid)
	(_dock.get_parent() as Control).visible = true
	for c in _dock.get_children():
		c.queue_free()
	for a in _apps:
		if a["name"] in DOCK:
			_dock.add_child(_app_button(a, Vector2(76, 76)))
		else:
			grid.add_child(_app_button(a, Vector2(84, 92)))


func _app_button(a: Dictionary, size: Vector2) -> Button:
	var b := Button.new()
	b.text = a["name"]
	b.custom_minimum_size = size
	var icon: Texture2D = Art.tex("ui/app-%s.png" % APP_ICON.get(a["name"], "story"))
	if icon:
		b.icon = icon
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.add_theme_constant_override("icon_max_width", 52 if size.y > 80 else 44)
	var cb: Callable = a["builder"]
	var nm: String = a["name"]
	b.pressed.connect(func() -> void:
		set_badge(nm, 0)
		_title.text = nm
		(_dock.get_parent() as Control).visible = false
		cb.call())
	var n := int(badges.get(nm, 0))
	if n > 0:
		var dot := Label.new()
		dot.text = str(n) if n < 10 else "9+"
		dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dot.custom_minimum_size = Vector2(24, 24)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#c8432f")
		sb.set_corner_radius_all(12)
		sb.border_color = INK
		sb.set_border_width_all(2)
		dot.add_theme_stylebox_override("normal", sb)
		dot.add_theme_color_override("font_color", Color.WHITE)
		dot.add_theme_font_size_override("font_size", 13)
		dot.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		dot.offset_left = -26
		dot.offset_top = 2
		b.add_child(dot)
	return b


func _clear(title: String) -> void:
	_title.text = title
	if _dock:
		(_dock.get_parent() as Control).visible = title.begins_with("Naija Street Life")
	for c in _screen.get_children():
		c.queue_free()


func _label(text: String, size := 16, colour := PAPER) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	_screen.add_child(l)
	return l


func _bar(label: String, value: float) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(110, 0)
	l.add_theme_color_override("font_color", PAPER)
	row.add_child(l)
	var pb := ProgressBar.new()
	pb.max_value = 100
	pb.value = value
	pb.show_percentage = false
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.custom_minimum_size = Vector2(0, 18)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#2f8a52") if value > 50 else (DANFO if value > 25 else Color("#a8382c"))
	fill.set_corner_radius_all(6)
	pb.add_theme_stylebox_override("fill", fill)
	row.add_child(pb)
	_screen.add_child(row)


# ---------- apps ----------

func _build_hustle() -> void:
	_clear("Hustle")
	if not jobs.active.is_empty():
		_label("ON THE JOB", 13, DANFO)
		_label(jobs.active["name"], 18)
		var c := Button.new()
		c.text = "Cancel this hustle"
		c.pressed.connect(func() -> void:
			cancel_job.emit()
			_build_hustle())
		_screen.add_child(c)
		_label(" ")
	_label("TODAY'S GIGS · %s" % Clock.weekday(), 13, DANFO)
	for o in jobs.offers:
		var card := VBoxContainer.new()
		_screen.add_child(card)
		var t := Label.new()
		t.text = "%s\nPays about ₦%s" % [o["name"], Life.fmt_naira(int(o["pay"]))]
		t.add_theme_color_override("font_color", PAPER)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(t)
		var b := Button.new()
		b.text = "Take it"
		b.disabled = not jobs.active.is_empty()
		var offer: Dictionary = o
		b.pressed.connect(func() -> void:
			accept_job.emit(offer)
			visible = false)
		card.add_child(b)
	_label("Real-world gigs from other players arrive with the marketplace.", 12, Color(1, 1, 1, 0.5))


func _build_bank() -> void:
	_clear("Bank")
	_label("Konfam Bank · Wallet", 13, DANFO)
	_label("₦%s" % Life.fmt_naira(Life.money), 34)
	_label("RECENT", 13, DANFO)
	for e in Life.ledger.slice(0, 15):
		var d := int(e["delta"])
		var day := int(e["t"]) / 1440 + 1
		_label("%s₦%s  %s  (day %d)" % ["+" if d >= 0 else "−", Life.fmt_naira(absi(d)), e["reason"], day], 13, Color("#9fd38a") if d >= 0 else Color("#e8a090"))


func _build_me() -> void:
	_clear("Me")
	_label("%s · %s" % [Life.hero.capitalize(), Life.mood_label()], 18)
	for n in Life.NEEDS:
		_bar(n.capitalize(), Life.needs[n])
	_label("SKILLS", 13, DANFO)
	for s in Life.SKILLS:
		_label("%s  ·  level %d" % [s.capitalize(), Life.level(s)], 14)
	_label("POCKET", 13, DANFO)
	if Life.inventory.is_empty():
		_label("Empty pocket. Na so life be sometimes.", 13)
	for id in Life.inventory:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = "%s ×%d" % [Life.item(id).get("name", id), int(Life.inventory[id])]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_color_override("font_color", PAPER)
		row.add_child(l)
		var use := Button.new()
		use.text = "Use"
		var item_id: String = id
		use.pressed.connect(func() -> void:
			Life.use_item(item_id)
			_build_me())
		row.add_child(use)
		_screen.add_child(row)
