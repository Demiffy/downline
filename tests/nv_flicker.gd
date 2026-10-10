# Night vision steadiness: the mean brightness of 40 frames in a row with the goggles on.
extends SceneTree
func _initialize() -> void:
	_run()
func _run() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 30: await process_frame
	for n in main.get_children():
		if n.has_method("_show_title"): n.queue_free()
	main.upgrades["NIGHT_VISION"] = true
	var p = main.player
	p.set_physics_process(false)
	p.frozen = true
	p.global_position = Vector3(2.0, 0.06, 10.0)
	p.rotation.y = 0.0
	for mode in ["off", "on"]:
		p.nv_on = mode == "on"
		for i in 20: await process_frame
		var vals := []
		for k in 40:
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.resize(64, 36)
			var s := 0.0
			for y in 36:
				for x in 64:
					s += img.get_pixel(x, y).get_luminance()
			vals.append(s / (64 * 36))
		var lo: float = vals.min()
		var hi: float = vals.max()
		print("%s: mean %.3f  min %.3f  max %.3f  swing %.1f%%" % [mode, vals.reduce(func(a, b): return a + b) / vals.size(), lo, hi, (hi - lo) / maxf(lo, 0.001) * 100.0])
	quit(0)
