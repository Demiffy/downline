# The crew car inside, close: the cargo shelves, the desk and its screens, the control stand. Needs a window.
# Run: godot --path . -s tests/train_shots.gd -- <out_dir>
extends SceneTree


func _initialize() -> void:
	_run()


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	main.hud.visible = false
	main.player.frozen = true
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.fov = 60
	var t: Vector3 = main.train.global_position
	for v in [["cargo", Vector3(-4.5, 2.4, 1.2), Vector3(-6.5, 1.3, -1.2)], ["desk", Vector3(5.2, 2.2, 0.8), Vector3(6.5, 1.75, -1.6)],
			["stand", Vector3(6.3, 2.2, 0.6), Vector3(8.0, 1.8, 0.6)], ["aisle", Vector3(-6.0, 2.0, 0.3), Vector3(6.0, 1.6, 0.0)],
			["monitor", Vector3(6.15, 2.0, -0.6), Vector3(6.15, 1.95, -1.6)]]:
		cam.global_position = t + v[1]
		cam.look_at(t + v[2])
		for i in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + "/" + v[0] + ".png")
	quit()
