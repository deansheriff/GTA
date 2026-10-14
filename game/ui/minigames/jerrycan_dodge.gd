extends MiniGame
## 2.6 "Fuel Queue Standoff": a slapstick brawl. Jerrycans fly in from the left, the right or high —
## dodge the right way. Nobody bleeds; everybody gets wet with (thankfully empty) jerrycans.

const DIRS := { "left": "◀ from the LEFT", "right": "from the RIGHT ▶", "high": "▲ HIGH (duck!)" }
const ROUNDS := 8

var _seq: Array = []
var _i := 0
var _hits := 0
var _left := 0.0
var _window := 1.6
var _prompt: Label
var _clock: ProgressBar
var _rng := RandomNumberGenerator.new()


func _build() -> void:
	set_title("Jerrycans incoming!")
	_prompt = label("", 30, DANFO)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock = bar(BAD)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	big_button("Lean right", func() -> void: _dodge("left"), row) # dodge AWAY from the side it comes from
	big_button("Duck", func() -> void: _dodge("high"), row)
	big_button("Lean left", func() -> void: _dodge("right"), row)


func _begin(_p: Dictionary) -> void:
	_rng.randomize()
	_seq.clear()
	for i in ROUNDS:
		_seq.append(DIRS.keys()[_rng.randi() % 3])
	_i = -1
	_hits = 0
	_next()


func _next() -> void:
	_i += 1
	if _i >= ROUNDS:
		var score := int(round(float(ROUNDS - _hits) / ROUNDS * 100.0))
		_prompt.text = "Brawl over. Queue restored. Diesel acquired." if score >= 50 else "You got bonked. Many times. Comedically."
		finish({ "score": score })
		return
	_prompt.text = "Jerrycan " + DIRS[_seq[_i]]
	_window = maxf(0.9, 1.6 - _i * 0.08)
	_left = _window
	if autoplay:
		await get_tree().create_timer(0.15).timeout
		_dodge(_seq[_i])


func _dodge(d: String) -> void:
	if not _running or _i >= ROUNDS:
		return
	if d != _seq[_i]:
		_hits += 1
	_next()


func _process(delta: float) -> void:
	if not _running or _i >= ROUNDS:
		return
	_left -= delta
	_clock.max_value = _window
	_clock.value = _left
	if _left <= 0.0:
		_hits += 1
		_next()
