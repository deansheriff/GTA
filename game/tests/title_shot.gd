extends SceneTree
## Screenshots of the living title screen (QA):
##   Godot --path game --script res://tests/title_shot.gd -- --shots=DIR

func _initialize() -> void:
	var dir := "user://shots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			dir = a.substr(8)
	DirAccess.make_dir_recursive_absolute(dir)
	await process_frame
	var title: CanvasLayer = load("res://ui/title_screen.gd").new()
	root.add_child(title)
	await create_timer(0.3).timeout
	title.set_map(load("res://world/map_data.gd").shared()) # as main.gd does once the city is built
	for i in 4:
		await create_timer(1.5).timeout
		root.get_viewport().get_texture().get_image().save_png("%s/title-%d.png" % [dir, i])
	title.set_ready(true)
	await create_timer(0.5).timeout
	root.get_viewport().get_texture().get_image().save_png("%s/title-menu.png" % dir)
	quit()
