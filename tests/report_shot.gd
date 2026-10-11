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
	var img := Image.create(320, 240, false, Image.FORMAT_RGB8)   # (a photograph for the clip)
	img.fill(Color(0.25, 0.22, 0.2))
	for y in 240:
		for x in 320:
			if (x / 40 + y / 40) % 2 == 0:
				img.set_pixel(x, y, Color(0.35, 0.3, 0.26))
	main.photo_log.append({"tex": ImageTexture.create_from_image(img), "stamp": "TEST"})
	main.report.show_report([3, "CHECKPOINT   21:40", 27, 1840, 164, 1, 3, "A"])
	var t0 := 0.0
	for t in [0.4, 1.6, 3.0, 4.3, 5.0]:
		await create_timer(t - t0).timeout
		t0 = t
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/r_%d.png" % [out, int(t * 10)])
	quit()
