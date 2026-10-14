extends MiniGame
## P3 money spraying: naira notes ride the beat toward the dancers. Tap SPRAY when a note crosses
## the line. Perfect = 100, good = 60, miss = 0; score is the average.

const LANE_H := 120.0
const TRAVEL := 1.6 # seconds from spawn to the hit line

var _lane: Control
var _beats := 20
var _interval := 0.6
var _t := 0.0
var _notes: Array = [] # [{t_hit, judged, grade}]
var _points := 0.0
var _combo := 0
var _feedback: Label
var _rng := RandomNumberGenerator.new()


func _build() -> void:
	set_title("Spray the money!")
	label("Tap SPRAY (or Space) when a note reaches the gold line. Stay on the beat and the dancers go wild.", 16, Color(1, 1, 1, 0.75))
	_lane = Control.new()
	_lane.custom_minimum_size = Vector2(0, LANE_H)
	_lane.draw.connect(_draw_lane)
	card.add_child(_lane)
	_feedback = label("", 24, DANFO)
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_button("SPRAY ₦", _tap)


func _begin(p: Dictionary) -> void:
	_rng.randomize()
	set_title(String(p.get("title", "Spray the money!")))
	_beats = int(p.get("beats", 20))
	_interval = 60.0 / float(p.get("bpm", 96))
	_notes.clear()
	for i in _beats:
		# Mostly on the beat, sometimes a double for flavour.
		var t := 1.2 + i * _interval
		_notes.append({ "t_hit": t, "judged": false, "grade": 0.0 })
	_t = 0.0
	_points = 0.0
	_combo = 0
	_feedback.text = "Ready…"


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_SPACE:
		get_viewport().set_input_as_handled()
		_tap()


func _tap() -> void:
	if not _running:
		return
	var best := -1
	var bd := 9.0
	for i in _notes.size():
		var n: Dictionary = _notes[i]
		if n["judged"]:
			continue
		var d := absf(float(n["t_hit"]) - _t)
		if d < bd:
			bd = d
			best = i
	if best < 0 or bd > 0.32:
		_combo = 0
		_feedback.text = "Off beat!"
		return
	var n: Dictionary = _notes[best]
	n["judged"] = true
	n["grade"] = 100.0 if bd < 0.09 else 60.0
	_points += float(n["grade"])
	_combo += 1
	_feedback.text = ("PERFECT! " if bd < 0.09 else "Good ") + ("×%d" % _combo if _combo > 2 else "")


func _process(delta: float) -> void:
	if not _running:
		return
	_t += delta
	for n in _notes:
		if not n["judged"]:
			if autoplay and absf(float(n["t_hit"]) - _t) < 0.03 and _rng.randf() < 0.9:
				_tap()
			elif _t - float(n["t_hit"]) > 0.32:
				n["judged"] = true
				_combo = 0
				_feedback.text = "Missed!"
	_lane.queue_redraw()
	if _t > float(_notes[-1]["t_hit"]) + 0.6:
		var score := int(round(_points / float(_beats)))
		_feedback.text = "The dancers are %s!" % ("screaming your name" if score >= 75 else ("dancing" if score >= 55 else "confused"))
		finish({ "score": score })


func _draw_lane() -> void:
	var w := _lane.size.x
	var hit_x := 90.0
	_lane.draw_rect(Rect2(0, 0, w, LANE_H), Color(0.1, 0.07, 0.05, 0.9))
	_lane.draw_line(Vector2(hit_x, 6), Vector2(hit_x, LANE_H - 6), DANFO, 5.0)
	for n in _notes:
		var dt: float = float(n["t_hit"]) - _t
		if dt > TRAVEL or dt < -0.35:
			continue
		var x := hit_x + dt / TRAVEL * (w - hit_x - 30.0)
		var col := Color("#3f8a3a") if not n["judged"] else (DANFO if float(n["grade"]) >= 100.0 else (GOOD if float(n["grade"]) > 0.0 else BAD))
		var r := Rect2(x - 26, LANE_H * 0.5 - 15, 52, 30)
		_lane.draw_rect(r, col)
		_lane.draw_rect(r, INK, false, 3.0)
		_lane.draw_string(ThemeDB.fallback_font, Vector2(x - 12, LANE_H * 0.5 + 6), "₦", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, PAPER)
