extends MiniGame
## 2.4 "Aso-Ebi Infiltration": the gate check. Match the invitation card (lace colour, gele, shoes)
## before the gateman looks up. Three guests, three rounds; one wrong piece and you're "not on the list".

const COLOURS := ["Purple", "Gold", "Wine", "Emerald"]
const GELES := ["Fan gele", "Sculpted tower", "Turban wrap", "No gele (bold)"]
const SHOES := ["Gold heels", "Purple sandals", "Agbada slippers", "Sneakers (risky)"]

var _round := 0
var _right := 0
var _want := []
var _pick := [0, 0, 0]
var _card: Label
var _rows: Array[OptionButton] = []
var _left := 0.0
var _clock: ProgressBar
var _rng := RandomNumberGenerator.new()


func _build() -> void:
	set_title("Gate check: Mama Chief's 90th")
	_card = label("", 20, DANFO)
	for opts in [COLOURS, GELES, SHOES]:
		var ob := OptionButton.new()
		ob.custom_minimum_size = Vector2(0, 48)
		for o in opts:
			ob.add_item(o)
		card.add_child(ob)
		_rows.append(ob)
	_clock = bar(DANFO)
	big_button("Walk in confidently", _submit)


func _begin(_p: Dictionary) -> void:
	_rng.randomize()
	_round = 0
	_right = 0
	_next()


func _next() -> void:
	if _round >= 3:
		var score := int(round(_right / 3.0 * 100.0))
		_card.text = "You're in. Act like you belong." if score >= 66 else "\"Madam, you are not on the list.\" (You climbed the back fence.)"
		finish({ "score": score })
		return
	_want = [_rng.randi() % 4, _rng.randi() % 4, _rng.randi() % 4]
	var who: String = ["Tunde", "Aunty Boss", "KC"][_round]
	_card.text = "Invitation for %s: %s lace · %s · %s" % [who, COLOURS[_want[0]], GELES[_want[1]], SHOES[_want[2]]]
	for r in _rows:
		r.select(_rng.randi() % 4)
	_left = 9.0
	if autoplay:
		await get_tree().create_timer(0.1).timeout
		for k in 3:
			_rows[k].select(_want[k])
		_submit()


func _submit() -> void:
	if not _running or _round >= 3:
		return
	var ok := true
	for k in 3:
		ok = ok and _rows[k].selected == _want[k]
	if ok:
		_right += 1
	_round += 1
	_next()


func _process(delta: float) -> void:
	if not _running or _round >= 3:
		return
	_left -= delta
	_clock.max_value = 9.0
	_clock.value = _left
	if _left <= 0.0:
		_round += 1
		_next()
