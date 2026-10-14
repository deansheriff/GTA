extends MiniGame
## 2.5 "Following the Money": the investigation board. Match each POS agent to the amount the
## treasurer pushed through them, using the market women's clues. The heroes only UNCOVER the
## structuring (Story Bible §8.1); every correct link is evidence.

const CASES := [
	{ "agent": "Mama Tosin (Oshodi umbrella)", "clue": "\"Nine withdrawals of ₦490,000, always just under the limit.\"", "amount": "₦4.41m" },
	{ "agent": "Bro Kunle (Yaba kiosk)", "clue": "\"Same man every Tuesday. Briefcase. Sweating.\"", "amount": "₦2.8m" },
	{ "agent": "Mrs. Bisi \"Receipts\"", "clue": "\"I kept a receipt for every one. My mother taught me.\"", "amount": "₦6.2m" },
	{ "agent": "Alhaji POS (Mushin)", "clue": "\"He paid in old notes. I didn't even know they still existed.\"", "amount": "₦1.9m" },
	{ "agent": "Chioma (Lekki)", "clue": "\"Transfers to 'Consultancy Ltd'. No consultancy. Just a gate.\"", "amount": "₦3.5m" },
]

var _cases: Array = []
var _i := 0
var _right := 0
var _agent: Label
var _clue: Label
var _btns: Array[Button] = []
var _note: Label


func _build() -> void:
	set_title("Investigation board")
	label("Who moved how much? Pick the amount that matches each agent's clue.", 16, Color(1, 1, 1, 0.75))
	_agent = label("", 22, DANFO)
	_clue = label("", 19)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	card.add_child(grid)
	for i in 5:
		var b := Button.new()
		b.custom_minimum_size = Vector2(170, 54)
		var idx := i
		b.pressed.connect(func() -> void: _pick(idx))
		grid.add_child(b)
		_btns.append(b)
	_note = label("", 16, Color(1, 1, 1, 0.7))


func _begin(_p: Dictionary) -> void:
	_cases = CASES.duplicate()
	_cases.shuffle()
	var amounts := CASES.map(func(c: Dictionary) -> String: return c["amount"])
	amounts.shuffle()
	for i in 5:
		_btns[i].text = amounts[i]
		_btns[i].disabled = false
	_i = -1
	_right = 0
	_next()


func _next() -> void:
	_i += 1
	if _i >= _cases.size():
		var score := int(round(_right / 5.0 * 100.0))
		_clue.text = "The red string connects everything back to Barrister Ledger."
		finish({ "score": score, "fx": { "evidence": _right / 2 + 1 } })
		return
	var c: Dictionary = _cases[_i]
	_agent.text = c["agent"]
	_clue.text = c["clue"] + "\n(Receipts suggest: " + ("about " if _i % 2 == 0 else "roughly ") + c["amount"].left(3) + "…)"
	if autoplay:
		await get_tree().create_timer(0.1).timeout
		for k in 5:
			if _btns[k].text == c["amount"]:
				_pick(k)
				return


func _pick(k: int) -> void:
	if not _running or _i >= _cases.size():
		return
	var c: Dictionary = _cases[_i]
	if _btns[k].text == c["amount"]:
		_right += 1
		_btns[k].disabled = true
		_note.text = "Linked: %s → %s. Evidence!" % [c["agent"], c["amount"]]
	else:
		_note.text = "That doesn't add up. Mama Nkem shakes her head."
	_next()
