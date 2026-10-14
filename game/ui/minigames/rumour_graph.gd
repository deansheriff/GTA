extends MiniGame
## 2.7 "Viral": seed gists into Lagos's networks (danfo, market, WhatsApp, church women, students)
## and watch them spread. Gists backed by receipts stick; false ones get debunked, cost Hype and
## Trust. Gist only ever targets fictional story characters (Story Bible §8.3).

const GISTS := [
	{ "text": "Barrister Ledger split ₦18m across 40 POS agents. (Receipts attached.)", "true": true },
	{ "text": "The \"Light for All\" transformer was paid for… with ₦0. (Diary page attached.)", "true": true },
	{ "text": "The Chief's agbada is powered by a hidden generator.", "true": false },
	{ "text": "Old notes in the Chief's warehouse. (Photo from Sule.)", "true": true },
	{ "text": "Pepper and Salt are secretly brothers. (No proof.)", "true": false },
	{ "text": "Teacher owns ten houses in Lekki.", "true": false },
]
const NETWORKS := ["Danfo", "Market", "WhatsApp", "Church women", "Students"]

var _shown: Array = []
var _round := 0
var _spread := 0.0
var _debunks := 0
var _gist: Label
var _graph: Control
var _lit := {}
var _note: Label


func _build() -> void:
	set_title("Gist network")
	_graph = Control.new()
	_graph.custom_minimum_size = Vector2(0, 170)
	_graph.draw.connect(_draw_graph)
	card.add_child(_graph)
	_gist = label("", 19)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	big_button("Seed it", func() -> void: _choose(true), row)
	big_button("Skip it", func() -> void: _choose(false), row)
	_note = label("", 16, Color(1, 1, 1, 0.75))


func _begin(_p: Dictionary) -> void:
	_shown = GISTS.duplicate()
	_shown.shuffle()
	_round = -1
	_spread = 0.0
	_debunks = 0
	_lit.clear()
	_next()


func _next() -> void:
	_round += 1
	if _round >= _shown.size():
		var score := int(clampf(_spread, 0.0, 100.0))
		_gist.text = "Final reach: %d%% of the ward is talking about the Chief." % score
		finish({ "score": score, "fx": { "stats": { "hype": score - _debunks * 150 }, "trust": -_debunks, "blocs": { "all": score / 10 } } })
		return
	_gist.text = "Gist: " + String(_shown[_round]["text"])
	_graph.queue_redraw()
	if autoplay:
		await get_tree().create_timer(0.1).timeout
		_choose(_shown[_round]["true"])


func _choose(plant: bool) -> void:
	if not _running or _round >= _shown.size():
		return
	var g: Dictionary = _shown[_round]
	if plant:
		if g["true"]:
			_spread += 34.0
			for i in 2:
				_lit[NETWORKS[(_round + i) % NETWORKS.size()]] = true
			_note.text = "It sticks! Receipts don't lie. Hype up."
		else:
			_debunks += 1
			_spread -= 15.0
			_note.text = "DEBUNKED. \"Na lie again,\" says the whole of WhatsApp. Hype −150, Trust −1."
	else:
		_note.text = "Skipped." + (" Wise: that one was fake." if not g["true"] else " That one was true, though.")
	_next()


func _draw_graph() -> void:
	var w := _graph.size.x
	var c := Vector2(w * 0.5, 85)
	_graph.draw_circle(c, 22, DANFO)
	_graph.draw_string(ThemeDB.fallback_font, c + Vector2(-14, 6), "KC", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, INK)
	for i in NETWORKS.size():
		var a := -PI / 2 + i * TAU / NETWORKS.size()
		var p := c + Vector2(cos(a) * w * 0.36, sin(a) * 66)
		var lit: bool = _lit.has(NETWORKS[i])
		_graph.draw_line(c, p, DANFO if lit else Color(1, 1, 1, 0.2), 4.0 if lit else 2.0)
		_graph.draw_circle(p, 16, GOOD if lit else Color(0.3, 0.25, 0.2))
		_graph.draw_string(ThemeDB.fallback_font, p + Vector2(-50, 32), NETWORKS[i], HORIZONTAL_ALIGNMENT_CENTER, 100, 14, PAPER)
