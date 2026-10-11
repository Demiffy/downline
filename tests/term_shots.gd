# The train's terminal: its screen with some commands run, the site map and a camera feed. Needs a window.
# Run: godot --path . -s tests/term_shots.gd -- <out_dir>
extends SceneTree


func _initialize() -> void:
	_run()


func shot(out: String, name: String, frames := 20) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	main.rng.seed = 7
	main.term.run("LEAVE_CHECKPOINT")
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	while main.busy:
		await process_frame
	main.term.open()
	await shot(out, "t_power", 4)
	main.term.run("HELP")
	await shot(out, "t_help")
	main.term.run("SITE_MAP" if main.term.commands.has("SITE_MAP") else "MAP")
	await shot(out, "t_map")
	main.term.run("VIEW_CAM 1")
	await shot(out, "t_cam_switch", 3)
	await shot(out, "t_cam", 60)
	main.term.close()
	await shot(out, "t_off", 6)
	quit()
