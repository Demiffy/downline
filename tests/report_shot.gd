# The shift report sliding in, typed, then stamped. Needs a window.
# Run: godot --path . -s tests/report_shot.gd -- <out_dir>
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
	main.report.show_report([3, "CHECKPOINT   21:40", 27, 1840, 164, 1, 3, "A"])
	for t in [0.5, 2.3, 2.7, 3.6]:
		await create_timer(t if t == 0.5 else t - [0.5, 2.3, 2.7, 3.6][[0.5, 2.3, 2.7, 3.6].find(t) - 1]).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/r_%d.png" % [out, int(t * 10)])
	quit()
