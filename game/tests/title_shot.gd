extends SceneTree
## Screenshots of the living title screen (QA):
##   Godot --path game --script res://tests/title_shot.gd -- --shots=DIR
## Draws the cut-out outlines too with --outlines (to check they hug the painting).

func _initialize() -> void:
	var dir := "user://shots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			dir = a.substr(8)
	DirAccess.make_dir_recursive_absolute(dir)
	await process_frame
	var title: CanvasLayer = load("res://ui/title_screen.gd").new()
	root.add_child(title)
	if "--outlines" in OS.get_cmdline_user_args():
		await process_frame
		var scene: Control = title.get_child(0).get_child(1)
		var stage: Node2D = scene.get_child(0)
		var cuts: Dictionary = load("res://ui/title_scene.gd").CUTOUTS
		for k in cuts:
			var l := Line2D.new()
			l.width = 2
			l.default_color = Color.MAGENTA
			for v: Vector2 in cuts[k]["poly"]:
				l.add_point(v)
			l.closed = true
			stage.add_child(l)
	for i in 4:
		await create_timer(1.5).timeout
		root.get_viewport().get_texture().get_image().save_png("%s/title-%d.png" % [dir, i])
	title.set_ready(true)
	await create_timer(0.5).timeout
	root.get_viewport().get_texture().get_image().save_png("%s/title-menu.png" % dir)
	quit()
