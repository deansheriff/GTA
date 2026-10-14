extends MiniGame
## 1.5 "Count it first": tap fast to count the stacks before someone "helps". One stack hides a page.

var _stacks := 16
var _count := 0
var _taps := 0
var _time := 18.0
var _left := 0.0
var _msg: Label
var _tally: Label
var _bar: ProgressBar
const TAPS_PER_STACK := 3
const NOTES := ["This one is crisp.", "This one smells like fish.", "Rubber band snapped. Again.", "Wait, this note looks… old?", "Somebody wrote a phone number on this one."]


func _build() -> void:
	set_title("Count it first")
	label("Tap COUNT as fast as you can. Three taps per bundle.", 16, Color(1, 1, 1, 0.75))
	_tally = label("", 30, DANFO)
	_msg = label("", 18)
	_bar = bar(DANFO)
	big_button("COUNT", _tap)


func _begin(p: Dictionary) -> void:
	_stacks = int(p.get("stacks", 16))
	_count = 0
	_taps = 0
	_left = _time
	_msg.text = "Tunde holds the torch. KC is not allowed to film."
	_update()


func _update() -> void:
	_tally.text = "Bundles counted: %d / %d" % [_count, _stacks]


func _tap() -> void:
	if not _running:
		return
	_taps += 1
	if _taps % TAPS_PER_STACK == 0:
		_count += 1
		_msg.text = NOTES[_count % NOTES.size()]
		if _count == _stacks / 2:
			_msg.text = "Wait. There's a folded PAGE stuck between these notes…"
		_update()
		if _count >= _stacks:
			finish({ "score": _count, "page": true })


func _process(delta: float) -> void:
	if not _running:
		return
	_left -= delta
	_bar.max_value = _time
	_bar.value = _left
	if autoplay and Engine.get_process_frames() % 3 == 0:
		_tap()
	if _left <= 0.0:
		_msg.text = "Time! \"Roughly a lot,\" says Tunde. Aunty is not satisfied."
		finish({ "score": _count, "page": _count >= _stacks / 2 })
