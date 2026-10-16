extends SceneTree
## QA: the danfo in every paint colour (tests/paint_shot.gd -- --shots=DIR).

func _initialize() -> void:
	var dir := "user://shots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			dir = a.substr(8)
	await process_frame
	var bg := ColorRect.new()
	bg.color = Color("#4a4a48")
	bg.size = Vector2(1280, 720)
	root.add_child(bg)
	var cols := ["", "#2f6f99", "#c8432f", "#2f8a52", "#76418a", "#d8b04a"]
	for i in cols.size():
		var d: Node2D = load("res://actors/danfo.gd").new()
		d.set_kind("danfo")
		d.position = Vector2(150 + i * 200, 360)
		root.add_child(d)
		d.set_paint(Color(cols[i]) if cols[i] != "" else Color(0, 0, 0, 0))
	await create_timer(0.5).timeout
	root.get_viewport().get_texture().get_image().save_png(dir + "/paints.png")
	quit()
