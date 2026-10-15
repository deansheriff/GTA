extends MiniGame
## Street "wahala": a slapstick fist fight (no blood; Story Bible). The opponent telegraphs a
## move; answer with the right one before the window closes: JAB when they open up, DUCK the
## wild swing, BLOCK the slap. Online fights use the server's sequence and send back the log.

const TELL := {
	"jab": "They drop their guard. JAB!",
	"duck": "A wild haymaker is coming. DUCK!",
	"block": "Open-palm slap incoming. BLOCK!",
}
# Pidgin lines pending native-speaker review.
const HIT_LINES := ["POW!", "Slap landed!", "Gbosa!", "Clean one!"]
const OUCH_LINES := ["You chop slap!", "Ehn! Right on the ear!", "Your cap don fly!", "The crowd says \"Ooooh!\""]

var _seq: Array = []
var _windows: Array = []
var _i := 0
var _left := 0.0
var _hits := 0
var _log: Array = []
var _me_pride: ProgressBar
var _them_pride: ProgressBar
var _them_label: Label
var _prompt: Label
var _fx: Label
var _clock: ProgressBar
var _rng := RandomNumberGenerator.new()


func _build() -> void:
	set_title("WAHALA!")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)
	var me := VBoxContainer.new()
	me.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(me)
	var l1 := Label.new()
	l1.text = "You"
	l1.add_theme_color_override("font_color", PAPER)
	me.add_child(l1)
	_me_pride = ProgressBar.new()
	_me_pride.show_percentage = false
	_me_pride.custom_minimum_size = Vector2(0, 14)
	me.add_child(_me_pride)
	var them := VBoxContainer.new()
	them.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(them)
	_them_label = Label.new()
	_them_label.add_theme_color_override("font_color", PAPER)
	_them_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	them.add_child(_them_label)
	_them_pride = ProgressBar.new()
	_them_pride.show_percentage = false
	_them_pride.custom_minimum_size = Vector2(0, 14)
	them.add_child(_them_pride)
	_prompt = label("", 26, DANFO)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fx = label("", 22, PAPER)
	_fx.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock = bar(BAD)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	card.add_child(btns)
	big_button("JAB", func() -> void: _move("jab"), btns)
	big_button("DUCK", func() -> void: _move("duck"), btns)
	big_button("BLOCK", func() -> void: _move("block"), btns)


## params: {opponent, seq?, windows?, intro?}
func _begin(p: Dictionary) -> void:
	_rng.randomize()
	_them_label.text = String(p.get("opponent", "Angry driver"))
	_seq = (p["seq"] as Array).duplicate() if p.has("seq") else []
	if _seq.is_empty():
		for i in 10:
			_seq.append(["jab", "duck", "block"][_rng.randi() % 3])
	_windows = (p["windows"] as Array).duplicate() if p.has("windows") else []
	_i = -1
	_hits = 0
	_log.clear()
	_me_pride.max_value = _seq.size()
	_me_pride.value = _seq.size()
	_them_pride.max_value = _seq.size()
	_them_pride.value = _seq.size()
	_fx.text = String(p.get("intro", "Crowd don gather. Somebody is filming."))
	_next()


func _window(i: int) -> float:
	return float(_windows[i]) if i < _windows.size() else maxf(0.8, 1.5 - i * 0.07)


func _next() -> void:
	_i += 1
	if _i >= _seq.size():
		var score := int(round(float(_hits) / _seq.size() * 100.0))
		_prompt.text = "You won the fight!" if _hits * 2 > _seq.size() else ("A draw. Una two don tire." if _hits * 2 == _seq.size() else "You lost. Your pride needs a plaster.")
		finish({ "score": score, "log": _log.duplicate() })
		return
	_prompt.text = TELL[_seq[_i]]
	_left = _window(_i)
	if autoplay:
		await get_tree().create_timer(0.25).timeout
		_move(_seq[_i])


func _move(m: String) -> void:
	if not _running or _i >= _seq.size():
		return
	_log.append({ "move": m, "t": snappedf(_window(_i) - _left, 0.01) })
	if m == _seq[_i]:
		_hits += 1
		if m == "jab":
			_them_pride.value -= 1
			_fx.text = HIT_LINES[_rng.randi() % HIT_LINES.size()]
		else:
			_fx.text = "Dodged! The crowd cheers."
		Sound.sfx("tap", 1.4)
	else:
		_me_pride.value -= 1
		_fx.text = OUCH_LINES[_rng.randi() % OUCH_LINES.size()]
		Sound.sfx("crash", 1.3)
		_shake()
	_next()


func _shake() -> void:
	if Settings.get_value("reduced_motion", false):
		return
	var tw := create_tween()
	var base := card.position
	for k in 4:
		tw.tween_property(card, "position", base + Vector2(randf_range(-8, 8), randf_range(-5, 5)), 0.03)
	tw.tween_property(card, "position", base, 0.03)


func _process(delta: float) -> void:
	if not _running or _i >= _seq.size():
		return
	_left -= delta
	_clock.max_value = _window(_i)
	_clock.value = _left
	if _left <= 0.0:
		_log.append({ "move": "none", "t": 99 })
		_me_pride.value -= 1
		_fx.text = "Too slow! " + OUCH_LINES[_rng.randi() % OUCH_LINES.size()]
		_next()
