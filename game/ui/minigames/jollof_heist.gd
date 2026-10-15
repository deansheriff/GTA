extends MiniGame
## Owambe jollof heist (M10 #9): the caterer aunty guards the cooler. Grab a spoonful when she
## looks away; grab while she's watching and she shouts you out of the hall.

var _watching := false
var _flip_t := 0.0
var _grabs := 0
var _need := 6
var _info: Label
var _aunty: Label
var _rng := RandomNumberGenerator.new()


func _build() -> void:
	set_title("Steal the jollof")
	_aunty = label("", 26, DANFO)
	_aunty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info = label("", 18, PAPER)
	big_button("GRAB", _grab)


func _begin(p: Dictionary) -> void:
	_rng.randomize()
	_need = int(p.get("need", 6))
	_grabs = 0
	_set_watch(false)


func _set_watch(w: bool) -> void:
	_watching = w
	_flip_t = _rng.randf_range(0.6, 1.4) if w else _rng.randf_range(0.8, 1.8)
	_aunty.text = "Aunty is WATCHING the cooler…" if w else "Aunty turned to greet a guest!"
	_info.text = "Spoons: %d / %d" % [_grabs, _need]


func _grab() -> void:
	if not _running:
		return
	if _watching:
		_aunty.text = "\"THIEF! Who invited you?!\""
		Sound.sfx("fail")
		finish({ "score": int(100.0 * _grabs / _need), "grabs": _grabs, "caught": true })
		return
	_grabs += 1
	Sound.sfx("tap", 1.3)
	_info.text = "Spoons: %d / %d" % [_grabs, _need]
	if _grabs >= _need:
		_aunty.text = "Belle full. Nobody saw. Party jollof!"
		finish({ "score": 100, "grabs": _grabs, "caught": false })


func _process(delta: float) -> void:
	if not _running:
		return
	_flip_t -= delta
	if _flip_t <= 0.0:
		_set_watch(not _watching)
	if autoplay and not _watching and _flip_t > 0.3 and _rng.randf() < delta * 4.0:
		_grab()
