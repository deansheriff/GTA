extends MiniGame
## Fishing from a canoe (M10 #11): cast, wait for the float to dip, strike in time, then reel:
## keep the line tension in the middle until the fish tires.

var _phase := "cast"
var _wait := 0.0
var _bite_t := 0.0
var _tension := 0.5
var _fish := 0.0 # fish strength left, 1 → 0
var _info: Label
var _float_lbl: Label
var _tbar: ProgressBar
var _fbar: ProgressBar
var _btn: Button
var _rng := RandomNumberGenerator.new()
var _casts := 3
var _caught := 0


func _build() -> void:
	set_title("Fishing")
	_info = label("", 18, PAPER)
	_float_lbl = label("", 30, DANFO)
	_float_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label("Line tension (keep it in the middle)", 13, PAPER)
	_tbar = bar(GOOD)
	_tbar.max_value = 1.0
	label("Fish strength", 13, PAPER)
	_fbar = bar(BAD)
	_fbar.max_value = 1.0
	_btn = big_button("Cast", _press)


## params: {casts?}
func _begin(p: Dictionary) -> void:
	_rng.randomize()
	_casts = int(p.get("casts", 3))
	_caught = 0
	_cast_ready()


func _cast_ready() -> void:
	_phase = "cast"
	_btn.text = "Cast"
	_info.text = "Casts left: %d · Fish caught: %d" % [_casts, _caught]
	_float_lbl.text = "~ ~ ~"
	_tbar.value = 0.5
	_fbar.value = 0.0
	if autoplay:
		_press.call_deferred()


func _press() -> void:
	if not _running:
		return
	match _phase:
		"cast":
			_casts -= 1
			_phase = "wait"
			_wait = _rng.randf_range(1.5, 4.0)
			_btn.text = "Strike!"
			_float_lbl.text = "~ o ~"
			Sound.sfx("splash")
		"wait":
			_info.text = "Too early! The fish swam off."
			_next()
		"bite":
			_phase = "reel"
			_tension = 0.5
			_fish = 1.0
			_btn.text = "Reel!"
			_info.text = "Tap to reel. Not too hard, not too soft."
		"reel":
			_tension += 0.12
			_fish -= 0.05


func _next() -> void:
	if _casts <= 0:
		finish({ "score": int(round(100.0 * _caught / 3.0)), "caught": _caught })
		return
	_cast_ready()


func _process(delta: float) -> void:
	if not _running:
		return
	match _phase:
		"wait":
			_wait -= delta
			if _wait <= 0.0:
				_phase = "bite"
				_bite_t = 0.9
				_float_lbl.text = "~ O ~  !!"
				Sound.sfx("tap", 0.7)
				if autoplay:
					_press.call_deferred()
		"bite":
			_bite_t -= delta
			if _bite_t <= 0.0:
				_info.text = "Too slow. It took the bait and left."
				_next()
		"reel":
			_tension -= delta * 0.28 + sin(Time.get_ticks_msec() * 0.006) * delta * 0.15
			if autoplay and _tension < 0.5:
				_press()
			if _tension > 0.3 and _tension < 0.75:
				_fish -= delta * 0.12
			_tbar.value = _tension
			_fbar.value = _fish
			if _tension >= 1.0:
				_info.text = "Snap! The line broke."
				_next()
			elif _tension <= 0.0:
				_info.text = "Slack line. It got away."
				_next()
			elif _fish <= 0.0:
				_caught += 1
				_info.text = "Got one!"
				Sound.sfx("success")
				_next()
